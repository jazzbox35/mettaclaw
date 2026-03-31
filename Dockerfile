# ==========================================
# Stage 1: Build Environment (Heavy tools stay here)
# ==========================================
FROM docker.io/library/swipl:latest as build

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      build-essential \
      python3 \
      python3-pip \
      python3-dev \
      ca-certificates \
      pkg-config \
      cmake \
      libopenblas-dev \
      libblas-dev \
      liblapack-dev \
      gfortran \
      libgflags-dev \
 && rm -rf /var/lib/apt/lists/*

# Install FAISS
RUN git clone --depth 1 https://github.com/facebookresearch/faiss.git /faiss
WORKDIR /faiss
RUN cmake -B build -DFAISS_ENABLE_GPU=OFF -DFAISS_ENABLE_PYTHON=OFF -DBUILD_SHARED_LIBS=OFF \
 && cmake --build build --config Release --parallel \
 && cmake --install build

# Install PeTTa
RUN git clone --depth 1 https://github.com/patham9/PeTTa.git /PeTTa
WORKDIR /PeTTa
RUN sh build.sh

# ==========================================
# Stage 2: Production Environment (Lean & Secure)
# ==========================================
FROM docker.io/library/swipl:latest as final

# Install ONLY runtime necessities (no compilers, no git, no nano)
# Also install 'gosu' to safely step down from root after setting the firewall
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 \
      python3-pip \
      iptables \
      gosu \
 && rm -rf /var/lib/apt/lists/*

# Create a non-root user and group
RUN groupadd -r mettagroup && useradd -r -g mettagroup mettauser

# Install Python dependencies
RUN pip3 install --no-cache-dir --break-system-packages janus-swi openai

# Set up the working directory
WORKDIR /app

# Copy compiled artifacts from the build stage
COPY --from=build /PeTTa /app/PeTTa
COPY --from=build /usr/local/lib/libfaiss.a /usr/local/lib/
# (Copy other necessary compiled libs as required by MORK/PeTTa)

# Download MeTTaClaw code (simulated here since we don't have git in final image)
# Ideally, you'd COPY this from your local context instead of cloning inside Docker.
COPY ./mettaclaw /app/repos/mettaclaw
RUN cp /app/repos/mettaclaw/run.metta ./ \
 && cp /app/repos/mettaclaw/firewall.sh /firewall.sh \
 && chmod +x /firewall.sh

# Lock down filesystem permissions
# 1. Give root ownership of everything (so the non-root user can't change it)
RUN chown -R root:root /app \
 && chmod -R 755 /app

# 2. Create a specific, isolated data directory for MeTTaClaw's legitimate writes (e.g., logs, Atomspace DB)
RUN mkdir -p /app/data \
 && chown -R mettauser:mettagroup /app/data

ENTRYPOINT ["/firewall.sh"]
# Use gosu in the CMD to step down to the non-root user before running the app
CMD ["gosu", "mettauser", "sh", "run.sh", "run.metta", "default"]
