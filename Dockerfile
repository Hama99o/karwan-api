# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t karwan_api .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name karwan_api karwan_api

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    # `development:test`, NOT `development`. Bundler drops a gem only when ALL
    # its groups are excluded — and this Gemfile has `group :development, :test`
    # plus a separate `group :test`, so excluding development alone dropped
    # nothing. Measured: the image shipped brakeman, rubocop, rspec, faker,
    # factory_bot and rswag-specs, 153 gem directories in total.
    #
    # DELIBERATE DIVERGENCE FROM hatiwal-api, which has the same line and the
    # same Gemfile shape and therefore ships them too. Karwan is not launching,
    # so the risk of correcting it is ours to take; Hatiwal improves on its next
    # build. Recorded in docs/NOTES.md, because this is a divergence TOWARD
    # correctness and whoever reconciles the two repos later needs to know which
    # direction it points.
    #
    # `rswag-api` and `rswag-ui` are in the DEFAULT group on purpose — they are
    # mounted in production — so this does not drop them. `rswag-specs`, which
    # only regenerates the swagger file, goes.
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# ── PRECOMPILE ASSETS, OR THE OPS CONSOLE SHIPS UNSTYLED ────────────────────
#
# COPIED FROM hatiwal-api/Dockerfile, which carries this step and the reason
# for it (correction 15). Karwan had dropped the line, and there was a blank
# gap where it belongs — found by building this image for the first time on
# 2026-09-17.
#
# Administrate is served by propshaft. Measured in the image built WITHOUT this
# step: `/rails/public/` contained only `robots.txt`, Propshaft's server
# middleware is **not** in the production stack (it is development-only), and
# `ActionDispatch::Static` serves from `public/`. So the console's HTML
# referenced `/assets/administrate/application-04100076.css` — resolved fine,
# because propshaft digests from the load path at runtime — and **nothing
# would have served it.** The admin console, which is Hamma9900's only
# operational surface (correction 16), would have rendered unstyled with every
# gate green.
#
# SECRET_KEY_BASE_DUMMY lets this run at build time without real credentials.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# ── DEVELOPMENT IMAGE — the one `docker compose up` runs ───────────────────
#
# PLACED BEFORE THE FINAL STAGE ON PURPOSE. Docker takes the LAST stage as the
# default build target, so a development stage appended to the end of this file
# would quietly become what `docker build .` and `kamal deploy` produce. It
# goes here so the production image stays the default and this one is reachable
# only by `--target development`.
#
# EVERYTHING `base` SETS IS WRONG HERE, and all three have to be undone:
#   RAILS_ENV=production      -> would read karwan_production and precompiled
#                                assets, not the dev database the seeds fill
#   BUNDLE_DEPLOYMENT=1       -> refuses any Gemfile.lock change, so adding a
#                                gem in development fails at boot rather than
#                                resolving
#   BUNDLE_WITHOUT=development:test -> drops rspec, factory_bot and faker, so
#                                the container could not run a single spec
#
# Source is BIND-MOUNTED at runtime rather than COPYed, so an edit on the host
# is live without a rebuild. `BUNDLE_PATH=/usr/local/bundle` is outside /rails
# and therefore survives the mount shadowing the working directory — gems are
# baked into the image, the code is not.
FROM base AS development

ENV RAILS_ENV="development" \
    BUNDLE_DEPLOYMENT="0" \
    BUNDLE_WITHOUT=""

# Same set the build stage installs: native gems need a compiler either way.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf "${BUNDLE_PATH}"/ruby/*/cache

# 3017, not 80. The rig, every doc and the emulator's 10.0.2.2:3017 depend on
# this number; see docker-compose.yml.
EXPOSE 3017
CMD ["./bin/rails", "server", "-b", "0.0.0.0", "-p", "3017"]


# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
