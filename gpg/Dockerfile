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
	sudo

USER gpg

RUN mkdir $HOME/.gnupg

RUN cd $HOME && \
	git clone https://aur.archlinux.org/gnupg-pkcs11-scd.git && \
	cd gnupg-pkcs11-scd && \
	makepkg -i --skippgpcheck --noconfirm
 
