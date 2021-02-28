FROM archlinux

MAINTAINER Marco Guerri

RUN useradd -m gpg

COPY --chown=gpg:gpg downgrade_glibc.sh /tmp

RUN chmod a+x /tmp/downgrade_glibc.sh && /tmp/downgrade_glibc.sh

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
	vim \
	patch \
	pinentry \
	pass

USER gpg

RUN mkdir $HOME/keys

RUN mkdir $HOME/keys/gnupg
RUN chmod 600 $HOME/keys/gnupg
RUN ln -s $HOME/keys/gnupg $HOME/.gnupg

RUN mkdir $HOME/config

# Requires second run, pacman upgrades glibc package
RUN chmod a+x /tmp/downgrade_glibc.sh && /tmp/downgrade_glibc.sh

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

RUN wget "https://gnupg.org/ftp/gcrypt/gnupg/gnupg-2.2.23.tar.bz2" -O $HOME/gnupg-2.2.23.tar.bz2 && \
	cd $HOME && \
        tar xvf gnupg-2.2.23.tar.bz2

COPY --chown=gpg:gpg files/0001_agent.patch /home/gpg/gnupg-2.2.23

RUN cd $HOME/gnupg-2.2.23 && patch -p0 < 0001_agent.patch && ./configure && make && sudo make install

COPY --chown=gpg:gpg config/gnupg-pkcs11-scd.conf /home/gpg/config
COPY --chown=gpg:gpg config/gpg-agent.conf /home/gpg/config
COPY --chown=gpg:gpg config/openssl.conf /home/gpg
COPY --chown=gpg:gpg scripts/init  /usr/sbin/init
COPY --chown=gpg:gpg scripts/generate_certificate  /home/gpg/scripts/generate_certificate

RUN chmod a+x /usr/sbin/init
RUN chmod a+x  $HOME/scripts/generate_certificate
RUN ln -s $HOME/keys $HOME/.tpm2_pkcs11
RUN sudo ln -s /usr/bin/pinentry /usr/local/bin/pinentry
