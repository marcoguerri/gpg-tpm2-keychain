Docker setup which provides an environment for [pass](https://www.passwordstore.org/) password manager, backed
by [gnupg-pkcs11-scd](https://github.com/alonbl/gnupg-pkcs11-scd) and [tpm2_pkcs11](https://github.com/tpm2-software/tpm2-pkcs11) backend to store gpg keys into TPM.
Documentation is still work in progress. Raw instructions below.

WARNING: This is a relatively complex setup with lots of links in the chain, Complexity is the enemy of security. I cannot guarantee the absence of bugs or configuration mistakes that would void the security of the whole approach. Therefore, use at your own risk.

# Auth model

A summary of the auth model, extracted from [tpm2-pkcs11 repo](https://github.com/tpm2-software/tpm2-pkcs11/blob/master/docs/ARCHITECTURE.md): all `tpm2_pkcs11` objects are stored under a peristent primary key in the owner hierarchy. `tpm2_pkcs11` library borrows several concepts that are smartcard specific. A `slot` is the physical smart card reader slot. For each slot, there could be one or more smartcards, each of which is associated with a token. A token maintains 2 objects under the primary key: one for the `SO` user, and the other for the `USER` user. The auth value for these objects is the `SO` or `USER` pin. The auth value is used to unseal an aes256 wrapping key, which in turn is used to encrypt all auth values for the objects in the token (keys and certificates that the token exposes for cryptographic operations). In this setup, the token is associated to a pre-existing transient TPM key stored outside of the TPM (in turn wrapped into a primary key in the owner hierarchy). This to allow for easy migration of this key to a different TPM (with associated policy) to give access to the same gpg-backed keychain on a different machine.

The migration policy used in this setup is a signed policy, which means that migration needs to be allowed by another authority via
signature. We use a TPM key generated on the same TPM that hosts the gpg key. Ideally the migration authority should be further protected
and stored on a different device. 

The instructions below explain how to setup `tpm2_pkcs11` store, generate the gpg key and migrate the TPM key to a different machine.
All persitent artifacts (e.g. keys, pass store, etc) are stored on `gpg_keys_volume` volume, which is bind mounted on `/home/gpg/keys`. 
If this volume gets lost (and there is no backup) access to all secrets is lost as well. Obviously, all TPM generated keys are bound
to that single TPM, so losing access to TPM, means also losing access to the keys.

# Store initialization

The pkcs11 store needs to be initialized with a token.
We'll initialize the store so the token will be associated to a transient external TPM object.

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py init --transient-parent tpm2-tools-default --path /home/gpg/keys | grep id | cut -d' ' -f 2-2
```

Create a token for the store we just initialized: (assuming PID 1):

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addtoken --path /home/gpg/keys --pid=1 --sopin=<SO_PIN> --userpin=<USER_PIN> --label=t_gpg
```

Create a transient key linked to the token. We create first a primary key in the owner hierachy that will wrap our key.
```
tpm2_createprimary -c primary.ctx
```

The key needs to be created as migrateable and a policy which protects its migration needs to be assocaited to the key. We want to
use a signed policy, so we generate first the signing key which will authorize the migration.

```
tpm2_create -C primary.ctx  -u migration_authority.pub -r migration_authority.priv -p <PASSPHRASE_MIGRATION_AUTHORITY>
```

Generate the policy which will allow the migration:

```
tpm2_load -C primary.ctx  -u migration_authority.pub -r migration_authority.priv -c migration_authority.ctx
tpm2_startauthsession -S session.ctx
tpm2_policysigned -S session.ctx -g sha256 -c /home/gpg/keys/migration_authority.ctx  --raw-data to_sign.bin
tpm2_sign  -c migration_authority.ctx -g sha256 -o migration_authority.sig to_sign.bin -p <PASSPHRASE_MIGRATION_AUTHORITY>
tpm2_policysigned -S session.ctx -g sha256 -s migration_authority.sig -c migration_authority.ctx  -L migration_policy.policy
tpm2_policycommandcode -S session.ctx -L migration_policy.policy TPM2_CC_Duplicate
tpm2_flushcontext session.ctx
```


Create a migratable key associated to that policy:
```
tpm2_create -C primary.ctx -u gpg.pub -r gpg.priv -a "sensitivedataorigin|userwithauth|decrypt|sign" -L migration_policy.signed  -p <ENCRYPTION_KEY_PASSPHRASE>
```

If we wanted to generate the key as persistent object inside the TPM, via `tpm2_ptool.py` itself, we would need to use the following command:
```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addkey \
    --algorithm=rsa2048 \
    --label=t_gpg \
    --key-label=gpg_key_1  \
    --userpin ${USER_PIN} \
    --path /home/gpg/.tpm2_pkcs11/
```
This is not necessary in this case as we are generating the key ourselves.

Link the key we just created with the token:

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py link --label=t_gpg --path /home/gpg/keys --userpin <USER_PIN> --key-label="k_gpg" gpg.pub gpg.priv --auth <ENCRYPTION_KEY_PASSPHRASE>
```

Now generate a certificate for the key, Inspect tokens and call `generate_certificate` is the corresponding URL.

```
p11tool --list-tokens
../scripts/generate_certificate <TOKEN_URL>
```

Associate the certificate to the token:

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addcert --path /home/gpg/keys --label t_gpg --key-label="k_gpg" cert.pem
```

Now generate the gpg key

```
gpgconf --kill all
gpg --card-status
gpg --expert --full-generate-key
```

We could either use `(13) Existing key` or `(14) Existing key from card`. With `(13)`, we would fist need to acquire they keygrip as follows:
```
# gpg-agent --server gpg-connect-agent
[...]
> SCD LEARN
[...]
```

The `KEY-FRIEDNLY` entry would give us the keygrip.

Later on it will be useful to list gpg keys with their full IDs:
```
gpg --keyid-format LONG  --list-keys
```

# Migrate key

The procedure below explains how to migrate the gpg key generated above. We'll assume that TPM `A`
is the origin TPM and TPM `B` is the destination TPM.

Create parent object on TPM `B` that will be used to wrap/transfer the key. Load it an get the public portion.

```
tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx
tpm2_readpublic -c primary.ctx -o new_parent.pub
```

Transfer new_parent.pub to the machine with TPM `A` and load the public part of the new parent key:

```
tpm2_loadexternal -C o -u new_parent.pub -c new_parent.ctx
```

Start a policy session to authorize the duplication on machine with TPM `A`
```
tpm2_startauthsession -S session.ctx --policy-session
tpm2_policysigned -S session.ctx -g sha256 -c /home/gpg/keys/migration_authority.ctx  --raw-data to_sign.bin
tpm2_sign -c /home/gpg/keys/migration_authority.ctx -g sha256  -o sig.rssa to_sign.bin -p
tpm2_policysigned -S session.ctx -g sha256 -c /home/gpg/keys/migration_authority.ctx  -s sig.rssa
tpm2_policycommandcode -S session.ctx -L migration_policy.policy TPM2_CC_Duplicate
```

Now key can be duplicated:
```
tpm2_duplicate  -C new_parent.ctx  -c gpg_key.ctx -G null  -r dup.dpriv -s dup.seed -p "session:session.ctx"
```

On TPM `A`, also read the public portion of the gpg key and move it to TPM `B`:
```
tpm2_readpublic -c gpg_key.ctx -o gpg_dup.pub
```

Copy over `dup.dpriv` and `dup.seed` to TPM `B`:

```
tpm2_import -C primary.ctx  -u gpg_dup.pub -i dup.dpriv -r gpg_key.priv -s dup.seed
tpm2_load -C primary.ctx -u gpg_dup.pub -r gpg_key.priv -c gpg_key.ctx
```


On TPM `B`, run the usual import and link steps:

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addtoken --path /home/gpg/keys --pid=1 --sopin=<SO_PIN> --userpin=<USER_PIN> --label=t_gpg
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py link --label=t_gpg --path /home/gpg/keys --userpin <USER_PIN> --key-label="k_gpg" gpg_ gpg.priv --auth
../scripts/generate_certificate <TOKEN_URL>
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addcert --path /home/gpg/keys --label t_gpg --key-label="k_gpg" cert.pem
```

Now, import gpg key from the primary TPM:
```
gpg --output key.gpg --export <GPG_KEY_EMAIL>
gpg --import key.gpg
```

Now the gpg key should be usable also on TPM `B`.


# Bugs
When decrypting a gpg message with the TPM backed key. gpg fails to extract the DEK from the corresponding frame, complaining that cipher algorithm is unknown in `get_it` in `pubkey-enc.c`. This happens because gpg-agent returns that random bytes padding at the begining of the frame has been removed (i.e. `padding = 0`), while this is not the case and DEK frame parsing picks up a random
byte as the `A` field (cipher algorithm). Patch `files/0001_agent.patch` fixes this by hard setting padding to `-1`, which
seems to be the value held by `padding` when using any other non-TPM backed key. As the time of writing, I haven't yet engaged
with upstream community to report the bug so the rogue patch is still part of this repo.
