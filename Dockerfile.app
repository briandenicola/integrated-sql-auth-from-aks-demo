FROM mcr.microsoft.com/dotnet/sdk:6.0 AS builder
WORKDIR /app
COPY src .
RUN dotnet restore 
RUN dotnet publish -c Release --nologo -o publish/linux

FROM bjd145/utils:3.10
RUN apt-get update && apt-get install -y krb5-user aspnetcore-runtime-6.0
COPY krb5/krb5.conf /etc/krb5.conf
WORKDIR /app
COPY --from=builder /app/publish/linux .