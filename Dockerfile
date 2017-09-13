FROM ruby:latest

# Throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

RUN mkdir -p /usr/src/app/lib/marcel
WORKDIR /usr/src/app

# Explicitly copy the minimum required for `bundle install` to successfully run.
# Copying just these files, not the whole source tree, means these steps can be
# cached by docker unless these files change. Changes to the main source or
# tests can be made without having to re-run bundle install.
COPY Gemfile /usr/src/app/
COPY Gemfile.lock /usr/src/app/
COPY marcel.gemspec /usr/src/app/
COPY lib/marcel/version.rb /usr/src/app/lib/marcel/
RUN ["bundle", "install"]

COPY . /usr/src/app

ENTRYPOINT ["bundle", "exec"]
CMD ["rake", "test"]
