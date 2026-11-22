# Security

- The helper runs `sudo apt-get` only in `deps` / `install-steam`, with packages from your configured Ubuntu archives.
- Your 3DMark CD key is written only into the local Proton prefix registry. It is never printed in full, logged, or sent anywhere. `logs` does not include `user.reg`.
- Steam config files are backed up (`*.3dmark-helper.bak`) before the first edit.
- No downloads from third-party hosts; Steam content comes through the Steam client.

Found a problem? Please open a private security advisory on GitHub (Security → Report a vulnerability) rather than a public issue.
