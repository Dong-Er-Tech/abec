FROM golang:1.24.0-alpine AS builder

RUN apk add --no-cache build-base cmake git openssl-dev linux-headers

# Build liboqs from source (required by cryptosuite/liboqs-go)
RUN git clone --depth 1 https://github.com/cryptosuite/liboqs.git /tmp/liboqs && \
    cd /tmp/liboqs && mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON -DCMAKE_C_FLAGS="-Wno-error=enum-int-mismatch" .. && \
    make -j$(nproc) && make install && \
    rm -rf /tmp/liboqs && \
    mkdir -p /usr/lib/pkgconfig && \
    printf 'prefix=/usr\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: liboqs\nDescription: Open Quantum Safe library\nVersion: 0.7.2\nLibs: -L${libdir} -loqs\nCflags: -I${includedir}\n' > /usr/lib/pkgconfig/liboqs.pc

# Build abec
WORKDIR /app/abec
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 go build -ldflags '-s -w' -o /usr/local/bin/abec .
RUN CGO_ENABLED=1 go build -ldflags '-s -w' -o /usr/local/bin/abectl ./cmd/abectl

# Build abewalletmlp (MLP/pseudonymCT wallet)
WORKDIR /app/abewalletmlp
RUN git clone --depth 1 https://github.com/pqabelian/abewalletmlp.git . && \
    CGO_ENABLED=1 go build -ldflags '-s -w' -o /usr/local/bin/abewalletmlp .

# Build abewallet (legacy/scheme 0 wallet, needed for mining before height 1000)
WORKDIR /app/abewallet
RUN git clone --depth 1 https://github.com/pqabelian/abewallet.git . && \
    CGO_ENABLED=0 go build -ldflags '-s -w' -o /usr/local/bin/abewallet .

FROM alpine:3.20

RUN apk add --no-cache libstdc++ libgcc ca-certificates tzdata

COPY --from=builder /usr/lib/liboqs* /usr/lib/
COPY --from=builder /usr/local/bin/abec /usr/local/bin/abec
COPY --from=builder /usr/local/bin/abectl /usr/local/bin/abectl
COPY --from=builder /usr/local/bin/abewalletmlp /usr/local/bin/abewalletmlp
COPY --from=builder /usr/local/bin/abewallet /usr/local/bin/abewallet

RUN mkdir -p /root/.abec /root/.abewalletmlp

EXPOSE 8667 8668 18667 18668 18888 18889 8333

ENTRYPOINT ["abec"]
