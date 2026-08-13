# Two stages: build with the full SDK, ship without it.
#
# The result is a single self-contained binary on a distroless base — no Dart
# runtime, no shell, no package manager, a few megabytes rather than a few
# hundred. Less to ship, less to patch, and nothing for anyone who does get in
# to run.
FROM dart:3.13 AS build

WORKDIR /src

# Copy only the manifests first so `pub get` is cached and does not re-run on
# every source edit.
# The lock file comes too, so the image built today and the image built in six
# months resolve the same dependency versions.
COPY server/pubspec.yaml server/pubspec.lock server/
COPY packages/ludo_engine/pubspec.yaml packages/ludo_engine/pubspec.yaml
COPY packages/ludo_protocol/pubspec.yaml packages/ludo_protocol/pubspec.yaml

# The path dependencies must resolve, so the packages need to exist even while
# only their manifests have been copied.
COPY packages/ludo_engine/lib packages/ludo_engine/lib
COPY packages/ludo_protocol/lib packages/ludo_protocol/lib

WORKDIR /src/server
RUN dart pub get

COPY server/ /src/server/
RUN dart pub get --offline
RUN dart compile exe bin/serve.dart -o /src/server/bin/ludo-server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /src/server/bin/ludo-server /app/ludo-server

ENV PORT=8080
EXPOSE 8080

# No shell in the image, so this is the process itself rather than a wrapper.
ENTRYPOINT ["/app/ludo-server"]
