FROM alpine:3.19 as builder
ARG TARGETPLATFORM
RUN echo "I'm building for $TARGETPLATFORM"

WORKDIR /tmp

# Build dependencies for aMule

# Download build dependencies
RUN apk add --no-cache autoconf automake 

# Install aMule
#RUN apk add --no-cache --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing amule amule-doc
ENV AMULE_VERSION 2.3.2
ENV UPNP_VERSION 1.14.13
ENV CRYPTOPP_VERSION CRYPTOPP_5_6_5
ENV BOOST_VERSION=1.80.0
ENV BOOST_VERSION_=1_80_0
ENV BOOST_ROOT=/usr/include/boost


# Upgrade required packages (build)
RUN apk --update add gd libpng libwebp pwgen sudo zlib bash && \
    apk --update add --virtual build-dependencies alpine-sdk \
                               bison g++ gcc gd-dev \
                               gettext gettext-dev git libpng-dev libwebp-dev \
                               libtool libsm-dev make musl-dev wget \
                               zlib-dev cmake \
                               gtk+3.0-dev glib-dev gdk-pixbuf-dev \
                               libx11-dev 
							   

# Get boost headers
RUN mkdir -p ${BOOST_ROOT} \
    && cd ${BOOST_ROOT} \
    && wget -q --timeout=30 --tries=3 "https://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/boost_${BOOST_VERSION_}.tar.gz/download" -O boost_${BOOST_VERSION_}.tar.gz \
    && tar zxf boost_${BOOST_VERSION_}.tar.gz --strip-components=1

# Build wxWidgets 3.2 from source
ENV WXWIDGETS_VERSION=3.2.5
RUN mkdir -p /tmp/wxwidgets \
    && cd /tmp/wxwidgets \
    && wget -q --timeout=30 --tries=3 "https://github.com/wxWidgets/wxWidgets/releases/download/v${WXWIDGETS_VERSION}/wxWidgets-${WXWIDGETS_VERSION}.tar.bz2" \
    && tar xfj wxWidgets-${WXWIDGETS_VERSION}.tar.bz2 \
    && cd wxWidgets-${WXWIDGETS_VERSION} \
    && ./configure \
        --prefix=/usr \
        --with-gtk=3 \
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
    && wget -q --timeout=30 --tries=3 "https://github.com/pupnp/pupnp/releases/download/release-${UPNP_VERSION}/libupnp-${UPNP_VERSION}.tar.bz2" \
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
ADD "https://api.github.com/repos/mercu01/amule/commits?per_page=1&sha=2.3.3_Broadband" latest_commit
RUN mkdir -p /build \
    && git clone --branch 2.3.3_Broadband --single-branch "https://github.com/mercu01/amule" \
    && cd amule* \
    && ./autogen.sh >/dev/null \
    && ./configure \
		--build=$(uname -m) \
        --prefix=/usr \
        --mandir=/usr/share/man \
        --enable-alc \
 		--enable-alcc \
 		--enable-amule-daemon \
 		--enable-amulecmd \
 		--enable-ccache \
 		--enable-optimize \
 		--enable-upnp \
 		--enable-webserver \
 		--disable-amule-gui \
        --enable-debug \
        --with-boost=${BOOST_ROOT} \
        --with-wx-config=wx-config-gtk3 \
        >/dev/null  \
    && make -j$(nproc) >/dev/null \
    && make DESTDIR=/build install 
#--disable-debug \

# Install a modern Web UI
RUN cd /build/usr/share/amule/webserver \
    && wget -q --timeout=30 --tries=3 -O AmuleWebUI-Reloaded-mercu01-amule-Broadband.zip https://github.com/mercu01/AmuleWebUI-Reloaded/archive/refs/heads/mercu01/amule-Broadband.zip \
    && unzip AmuleWebUI-Reloaded-mercu01-amule-Broadband.zip \
    && mv AmuleWebUI-Reloaded-mercu01-amule-Broadband AmuleWebUI-Reloaded \
    && rm -rf AmuleWebUI-Reloaded-mercu01-amule-Broadband.zip AmuleWebUI-Reloaded/doc-images

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
