FROM archlinux/base

MAINTAINER Marco Guerri

RUN useradd -m gpg

RUN echo "gpg ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN pacman -Syu --noconfirm \
        gnupg \
        git \
        fakeroot \
        binutils \
        nss \
        libtool \
        m4 \
        automake \
        autoconf \
        gcc \
        file \
        openssl \
        libgcrypt  \
        pkg-config \
        make \
        gnutls \
        nss \
        wget \
        tar \
        pkcs11-helper \
        sudo \
        pkgconfig \
        autoconf-archive \
        tpm2-tss \
        libyaml \
        tpm2-tools \
        python3 \
        python-yaml \
        python-cryptography \
        python-pyasn1-modules \
        p11-kit \
        pkcs11-helper \
        libp11 \
        tpm2-tss-engine \
        opensc \
	vim

USER gpg

RUN mkdir $HOME/.gnupg

RUN cd $HOME && \
        git clone https://aur.archlinux.org/gnupg-pkcs11-scd.git && \
        cd gnupg-pkcs11-scd && \
        makepkg -i --skippgpcheck --noconfirm

RUN cd $HOME && \
        git clone https://github.com/tpm2-software/tpm2-pkcs11.git \
                --depth 1 \
                --branch 1.4.0

RUN cd $HOME/tpm2-pkcs11 && \
                ./bootstrap && \
                ./configure && \
                make && \
                sudo make install

COPY --chown=gpg:gpg config/gnupg-pkcs11-scd.conf /home/gpg/.gnupg
COPY --chown=gpg:gpg config/gpg-agent.conf /home/gpg/.gnupg
COPY --chown=gpg:gpg config/openssl.conf /home/gpg
COPY --chown=gpg:gpg scripts/init  /usr/sbin/init
COPY --chown=gpg:gpg scripts/generate_certificate  /home/gpg/scripts/generate_certificate
RUN chmod a+x /usr/sbin/init
RUN chmod a+x /home/gpg/scripts/generate_certificate
