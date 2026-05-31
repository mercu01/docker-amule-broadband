FROM alpine:3.19 as builder
ARG TARGETPLATFORM
RUN echo "I'm building for $TARGETPLATFORM"

WORKDIR /tmp

# Build dependencies for aMule

# Download build dependencies (cmake is in build-dependencies below)
# autoconf/automake no longer needed — upstream switched to CMake

# Install aMule
#RUN apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing amule amule-doc
ENV AMULE_VERSION 2.3.2
ENV UPNP_VERSION 1.14.13
ENV CRYPTOPP_VERSION CRYPTOPP_5_6_5
ENV BOOST_VERSION=1.80.0
ENV BOOST_VERSION_=1_80_0


# Upgrade required packages (build)
RUN apk --update add gd libpng libwebp pwgen sudo zlib bash && \
    apk --update add --virtual build-dependencies alpine-sdk \
    bison g++ gcc gd-dev \
    gettext gettext-dev git libpng-dev libwebp-dev \
    libtool libsm-dev make musl-dev wget \
    zlib-dev cmake boost-dev readline-dev curl-dev \
    gtk+3.0-dev glib-dev gdk-pixbuf-dev \
    libx11-dev \
    && git config --global http.sslVerify false


# Boost is installed via boost-dev package above

# Build wxWidgets 3.2 from source
ENV WXWIDGETS_VERSION=3.2.5
RUN mkdir -p /tmp/wxwidgets \
    && cd /tmp/wxwidgets \
    && wget -q --no-check-certificate --timeout=30 --tries=3 "https://github.com/wxWidgets/wxWidgets/releases/download/v${WXWIDGETS_VERSION}/wxWidgets-${WXWIDGETS_VERSION}.tar.bz2" \
    && tar xfj wxWidgets-${WXWIDGETS_VERSION}.tar.bz2 \
    && cd wxWidgets-${WXWIDGETS_VERSION} \
    && ./configure \
    --prefix=/usr \
    --with-gtk=3 \
    --with-libcurl \
    --with-opengl=no \
    --enable-unicode \
    --enable-intl \
    --disable-epollloop \
    && make -j$(nproc) \
    && make install \
    && make DESTDIR=/build install \
    && ln -sf /usr/bin/wx-config /usr/bin/wx-config-gtk3

# Build libupnp
RUN mkdir -p /build \
    && cd /tmp \
    && wget -q --no-check-certificate --timeout=30 --tries=3 "https://github.com/pupnp/pupnp/releases/download/release-${UPNP_VERSION}/libupnp-${UPNP_VERSION}.tar.bz2" \
    && tar xfj libupnp-${UPNP_VERSION}.tar.bz2 \
    && cd libupnp* \
    && ./configure --prefix=/usr >/dev/null \
    && make -j$(nproc) >/dev/null \
    && make install \
    && make DESTDIR=/build install

# Build crypto++
RUN mkdir -p /build \
    && git clone --branch master --single-branch "https://github.com/weidai11/cryptopp"  \
    && cd cryptopp* \
    && make CXXFLAGS="${CXXFLAGS} -DNDEBUG -fPIC" -j$(nproc) -f GNUmakefile dynamic >/dev/null \
    && make PREFIX="/usr" install \
    && make DESTDIR=/build PREFIX="/usr" install

# Build amule from source
ADD "https://api.github.com/repos/mercu01/amule/commits?per_page=1&sha=master" latest_commit
RUN mkdir -p /build \
    && git clone --branch master --single-branch "https://github.com/mercu01/amule" \
    && cd amule* \
    && cmake -B build \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_DAEMON=YES \
    -DBUILD_AMULECMD=YES \
    -DBUILD_ALC=YES \
    -DBUILD_ALCC=YES \
    -DBUILD_WEBSERVER=YES \
    -DBUILD_MONOLITHIC=NO \
    -DBUILD_REMOTEGUI=NO \
    -DENABLE_UPNP=YES \
    && cmake --build build -j$(nproc) \
    && DESTDIR=/build cmake --install build

# Install a modern Web UI
RUN cd /build/usr/share/amule/webserver \
    && wget -q --no-check-certificate --timeout=30 --tries=3 -O AmuleWebUI-Reloaded-master.zip https://github.com/mercu01/AmuleWebUI-Reloaded/archive/refs/heads/master.zip \
    && unzip AmuleWebUI-Reloaded-master.zip \
    && mv AmuleWebUI-Reloaded-master AmuleWebUI-Reloaded \
    && rm -rf AmuleWebUI-Reloaded-master.zip AmuleWebUI-Reloaded/doc-images

FROM alpine:3.19

LABEL maintainer="mercu01@gmail.com original author -> ngosang@hotmail.es"

# Install runtime packages
RUN apk add --no-cache libgcc libpng libstdc++ libupnp libintl musl zlib tzdata pwgen mandoc curl \
    gtk+3.0 glib gdk-pixbuf libx11 pcre2-dev libedit gdb
# Copy build directory
COPY --from=builder /build/usr/bin/alcc /usr/bin/alcc
COPY --from=builder /build/usr/bin/amulecmd /usr/bin/amulecmd
COPY --from=builder /build/usr/bin/amuled /usr/bin/amuled
COPY --from=builder /build/usr/bin/amuleweb /usr/bin/amuleweb
COPY --from=builder /build/usr/bin/ed2k /usr/bin/ed2k
COPY --from=builder /build/usr/share/amule /usr/share/amule
COPY --from=builder /build/usr/lib/ /usr/lib/

# Check binaries are OK
RUN ldd /usr/bin/alcc && \
    ldd /usr/bin/amulecmd && \
    ldd /usr/bin/amuled && \
    ldd /usr/bin/amuleweb

# Add entrypoint
COPY entrypoint.sh /home/amule/entrypoint.sh

WORKDIR /home/amule

EXPOSE 4711/tcp 4712/tcp 4662/tcp 4665/udp 4672/udp

ENTRYPOINT ["sh", "/home/amule/entrypoint.sh"]

# HELP
#
# => Build Docker image
#docker buildx build --platform linux/arm64/v8 -t mercu/builder-amule:arm64 .
# => Push Dockerhub image
#docker push mercu/builder-amule:arm64
