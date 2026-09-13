# syntax=docker/dockerfile:1

# Stage 1: build - uses the big SDK image (about 1 GB). It never ships.
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy only the project file first, then restore.
# Docker caches this layer, so NuGet restore is skipped when only code changes.
COPY ["SCAA-Final-Web/SCAA-Final-Web.csproj", "SCAA-Final-Web/"]
RUN dotnet restore "SCAA-Final-Web/SCAA-Final-Web.csproj"

# Now copy the rest of the source and publish.
COPY . .
WORKDIR /src/SCAA-Final-Web
RUN dotnet publish "SCAA-Final-Web.csproj" \
        -c $BUILD_CONFIGURATION \
        -o /app/publish \
        /p:UseAppHost=false


# Stage 2: runtime - small image (about 110 MB). Only this one is shipped.
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final

# Build arguments, filled in by the CI pipeline.
ARG APP_VERSION=0.0.0-local
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown

# --- Required metadata (OCI standard labels) -------------------------------
LABEL org.opencontainers.image.title="SCAA-Final-Web" \
      org.opencontainers.image.description="SCAA DevOps final project - ASP.NET Core MVC web application" \
      org.opencontainers.image.authors="Nikoloz Chkhartishvili <nika.chkhartishviliyt7@gmail.com>" \
      org.opencontainers.image.vendor="SCAA DevOps Course" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="MIT" \
      maintainer="Nikoloz Chkhartishvili <nika.chkhartishviliyt7@gmail.com>"

WORKDIR /app

# The application listens on port 8080 (plain HTTP) inside the container.
ENV ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    APP_VERSION=${APP_VERSION}

COPY --from=build /app/publish .

# Run as a non-root user. $APP_UID (=1654) is defined by the Microsoft base image.
USER $APP_UID

EXPOSE 8080

ENTRYPOINT ["dotnet", "SCAA-Final-Web.dll"]