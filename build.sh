#!/bin/bash

xcodebuild install

pkgbuild --root "/tmp/SelfServiceUpdateNotifier.dst/" \
--scripts "scripts/" \
--identifier "de.uni-erlangen.rrze.SelfServiceUpdateNotifier" \
--version "1.0" \
--install-location "/" \
--sign "Developer ID Installer: Universitaet Erlangen-Nuernberg RRZE (C8F68RFW4L)" \
"/tmp/SelfServiceUpdateNotifier.pkg"

rm -rf /tmp/SelfServiceUpdateNotifier.dst


