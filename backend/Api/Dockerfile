# The API as a container, so the deploy is a config change rather than an afternoon.
#
# Nothing here deploys anything — it only makes the artefact. Choosing a host, holding its
# credentials and pressing the button are decisions for a person, not something a build script
# should have made on their behalf.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Restore before copying the rest, so a source change does not re-download the world.
COPY Api/Kvitta.Api.csproj Api/
RUN dotnet restore Api/Kvitta.Api.csproj

COPY Api/ Api/
RUN dotnet publish Api/Kvitta.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Non-root. The API talks to Postgres and writes nothing to disk, so there is no reason for it to
# be able to.
RUN useradd --uid 10001 --create-home --shell /usr/sbin/nologin kvitta
USER 10001

COPY --from=build /app .

# No signing key, no connection string, and no secret of any kind baked in. The host refuses to
# start without Auth__SigningKey, which is the intended behaviour: a container that boots with a
# key someone can read out of the image is worse than one that does not boot.
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

# The health endpoint M3 added, used here rather than only by an external monitor — a container
# that has stopped answering should be replaced without waiting for someone to notice.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD ["/bin/sh", "-c", "curl -fsS http://localhost:8080/health || exit 1"]

ENTRYPOINT ["dotnet", "Kvitta.Api.dll"]
