FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 8080
EXPOSE 8081

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["SCAA-Final-Web/SCAA-Final-Web.csproj", "SCAA-Final-Web/"]
RUN dotnet restore "./SCAA-Final-Web/SCAA-Final-Web.csproj"
COPY . .
WORKDIR "/src/SCAA-Final-Web"
RUN dotnet build "./SCAA-Final-Web.csproj" -c $BUILD_CONFIGURATION -o /app/build

FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./SCAA-Final-Web.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "SCAA-Final-Web.dll"]