FROM debian:bookworm-slim

ARG TZ=America/New_York
ENV TZ="$TZ"

ARG USERNAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

# Install essential tools — GNU coreutils/grep/sed/awk come with base Debian
# Add networking, firewall, dev tools, and useful CLI utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  bash-completion \
  ca-certificates \
  curl \
  wget \
  git \
  less \
  procps \
  sudo \
  man-db \
  unzip \
  gnupg2 \
  openssh-client \
  # Firewall tools
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  # CLI utilities
  jq \
  nano \
  vim-tiny \
  fzf \
  tmux \
  diffutils \
  patch \
  file \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --gid $USER_GID $USERNAME && \
  useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME

# Command history directory (mount point — host dir or volume)
RUN mkdir /commandhistory && \
  chown $USERNAME:$USERNAME /commandhistory

# Set up bash history in profile
RUN echo 'export HISTFILE=/commandhistory/.bash_history' >> /home/$USERNAME/.bashrc && \
  echo 'export PROMPT_COMMAND="history -a"' >> /home/$USERNAME/.bashrc && \
  echo 'export HISTSIZE=10000' >> /home/$USERNAME/.bashrc && \
  echo 'export HISTFILESIZE=20000' >> /home/$USERNAME/.bashrc

ENV DEVCONTAINER=true

# Create workspace and config directories
RUN mkdir -p /workspace /home/$USERNAME/.claude && \
  chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude

WORKDIR /workspace

# Install git-delta for better diffs
ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget -q "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install Claude Code CLI (binary, not npm)
USER $USERNAME
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
USER root

# Bake claude-template into image for first-run bootstrap
COPY --chown=$USER_UID:$USER_GID claude-template/ /opt/claude-template/

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "$USERNAME ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/$USERNAME-firewall && \
  chmod 0440 /etc/sudoers.d/$USERNAME-firewall

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

USER $USERNAME
ENV SHELL=/bin/bash
ENV EDITOR=nano
ENV VISUAL=nano

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
