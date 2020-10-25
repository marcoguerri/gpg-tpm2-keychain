Docker setup to run gnupg-pkcs11-scd and tpm2_pkcs11 backend to store gpg keys into TPM.
Documentation is still work in process. Raw instructions below.

# Initialize keys backed by TPM


The pkcs11 store needs to be initialized with a token.

We'll initialize the store to use a transient external TPM object

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py init --transient-parent tpm2-tools-default --path /home/gpg/keys | grep id | cut -d' ' -f 2-2
```

Create a token for the store we just initialized: (assuming PID 1):

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addtoken --path /home/gpg/keys --pid=1 --sopin=<SO_PIN> --userpin=<USER_PIN> --label=t_gpg
```

Create a transient key to link to the token
```
tpm2_createprimary -c primary.ctx
```


The key needs to be created as migrateable and a policy which protects its migration needs to be assocaited to the key.

Generate the policy. Start by generating a signing key which is the one that will have to authorize migration. 
Ideally this key should live yet on another system.

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

Link the key we just created with the token:

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py link --label=t_gpg --path /home/gpg/keys --userpin <USER_PIN> --key-label="k_gpg" gpg.pub gpg.priv --auth <ENCRYPTION_KEY_PASSPHRASE>
```

Now generate a certificate for the key, Inspect tokens:

```
p11tool --list-tokens
../scripts/generate_certificate <TOKEN_URL>
```

Associate the certificate to the token:

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addcert --path /home/gpg/keys --label t_gpg --key-label="k_gpg" cert.pem
```


Now generate the gpg key:

```
gpgconf --kill all
gpg --card-status
gpg --expert --full-generate-key
```


In order to list gpg keys with their full IDs:
```
gpg --keyid-format LONG  --list-keys
```

# Migrate key

Create parent object that will be used to wrap/transfer the key. Load it an get the public portion.
````
tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx
tpm2_readpublic -c primary.ctx -o new_parent.pub
```

Transfer new_parent.pub to the primary TOM.

On the primary TPM, load the public part of the new parent key:

```
tpm2_loadexternal -C o -u new_parent.pub -c new_parent.ctx
```

Start a policy session to authorize the duplication:

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

Also read the public portion of the gpg key and move it to the secondary TPM.
```
tpm2_readpublic -c gpg_key.ctx -o gpg_dup.pub
```

Copy over dup.dpriv and dup.seed to the secondary TPM.

```
tpm2_import -C primary.ctx  -u gpg_dup.pub -i dup.dpriv -r gpg_key.priv -s dup.seed
tpm2_load -C primary.ctx -u gpg_dup.pub -r gpg_key.priv -c gpg_key.ctx
```


On the secondary TPM, run the usual import and link steps:

```
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addtoken --path /home/gpg/keys --pid=1 --sopin=<SO_PIN> --userpin=<USER_PIN> --label=t_gpg
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py link --label=t_gpg --path /home/gpg/keys --userpin <USER_PIN> --key-label="k_gpg" gpg_ gpg.priv --auth
../scripts/generate_certificate <TOKEN_URL>
/home/gpg/tpm2-pkcs11/tools/tpm2_ptool.py addcert --path /home/gpg/keys --label t_gpg --key-label="k_gpg" cert.pem
```

Now, import gpg key from the primary TPM:
```
gpg --output key.gpg --export marco.guerri@fastmail.com
gpg --import key.gpg
```


