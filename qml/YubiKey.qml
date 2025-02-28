import QtQuick 2.5
import io.thp.pyotherside 1.4
import "utils.js" as Utils
import "images.js" as Images

// @disable-check M300
Python {
    id: py

    property bool yubikeyModuleLoaded: false
    property bool yubikeyReady: false
    property var queue: []

    property var availableDevices: []
    property var availableReaders: []

    property var currentDevice
    property bool currentDeviceValidated

    property bool pinIsBlocked: false
    property bool deviceRemoved: false
    property bool deviceBack: false

    property var fingerprints: []
    property var credentials: []

    property bool isPolling: false

    property bool isWinNonAdmin: false

    // Check if a application such as OATH, PIV, etc
    // is enabled on the current device.
    function currentDeviceEnabled(app) {
        if (!!currentDevice) {
            if (currentDevice.isNfc) {
                return currentDevice.nfcAppEnabled.includes(app)
            } else {
                return currentDevice.usbAppEnabled.includes(app)
            }
        } else {
            return false
        }
    }

    // Check if a application such as OATH, PIV, etc
    // is supported on the current device.
    function currentDeviceSupported(app) {
        if (!!currentDevice) {
            if (currentDevice.isNfc) {
                return currentDevice.nfcAppSupported.includes(app)
            } else {
                return currentDevice.usbAppSupported.includes(app)
            }
        } else {
            return false
        }
    }

    signal enableLogging(string logLevel, string logFile)
    signal disableLogging

    // Timestamp in seconds for when it's time for the
    // next calculateAll call. -1 means never
    property int nextCalculateAll: -1

    Component.onCompleted: {
        importModule('site', function () {
            call('site.addsitedir', [appDir + '/pymodules'], function () {
                addImportPath(urlPrefix + '/py')
                importModule('yubikey', function () {
                    yubikeyModuleLoaded = true

                    doCall('yubikey.controller.is_win_non_admin', [], function(resp) {
                        isWinNonAdmin = resp.winNonAdmin
                    })
                })
            })
        })
    }

    onEnableLogging: {
        doCall('yubikey.init_with_logging',
               [logLevel || 'DEBUG', logFile || null], function () {
                   yubikeyReady = true
               })
    }

    onDisableLogging: {
        doCall('yubikey.init', [], function () {
            yubikeyReady = true
        })
    }

    onYubikeyModuleLoadedChanged: runQueue()
    onYubikeyReadyChanged: runQueue()

    function isPythonReady(funcName) {
        if (funcName.startsWith("yubikey.init")) {
            return yubikeyModuleLoaded
        } else {
            return yubikeyReady
        }
    }

    function runQueue() {
        var oldQueue = queue
        queue = []
        for (var i in oldQueue) {
            doCall(oldQueue[i][0], oldQueue[i][1], oldQueue[i][2])
        }
    }

    function doCall(func, args, cb) {
        if (!isPythonReady(func)) {
            queue.push([func, args, cb])
        } else {
            call(func, args.map(JSON.stringify), function (json) {
                if (cb) {
                    try {
                        cb(json ? JSON.parse(json) : undefined)
                    } catch (err) {
                        console.log(err, json)
                    }
                }
            })
        }
    }

    function supportsNewInterfaces() {
        return currentDevice.version.startsWith('5');
    }

    function isYubiKeyFIPS(device) {
        return device.name === 'YubiKey FIPS'
    }

    function getYubiKeyImageSource(currentDevice) {
        return "../images/" + Images.getYubiKeyImageName(currentDevice) + ".png";
    }

    function getCurrentDeviceImage() {
        if (!!currentDevice) {
            return getYubiKeyImageSource(currentDevice)
        } else {
            return ""
        }
    }

    function slotsStatus(cb) {
        doCall('yubikey.controller.slots_status', [], cb)
    }

    function eraseSlot(slot, cb) {
        doCall('yubikey.controller.erase_slot', [slot], cb)
    }

    function swapSlots(cb) {
        doCall('yubikey.controller.swap_slots', [], cb)
    }

    function serialModhex(cb) {
        doCall('yubikey.controller.serial_modhex', [], cb)
    }

    function randomUid(cb) {
        doCall('yubikey.controller.random_uid', [], cb)
    }

    function randomKey(bytes, cb) {
        doCall('yubikey.controller.random_key', [bytes], cb)
    }

    function programChallengeResponse(slot, key, touch, cb) {
        doCall('yubikey.controller.program_challenge_response',
               [slot, key, touch], cb)
    }

    function programStaticPassword(slot, password, keyboardLayout, cb) {
        doCall('yubikey.controller.program_static_password',
               [slot, password, keyboardLayout], cb)
    }

    function programOathHotp(slot, key, digits, cb) {
        doCall('yubikey.controller.program_oath_hotp', [slot, key, digits], cb)
    }

    function generateStaticPw(keyboardLayout, cb) {
        doCall('yubikey.controller.generate_static_pw', [keyboardLayout], cb)
    }

    function programOtp(slot, publicId, privateId, key, upload, cb) {
        doCall('yubikey.controller.program_otp',
               [slot, publicId, privateId, key, upload, appVersion], cb)
    }

    function checkUsbDescriptorsChanged(cb) {
        doCall('yubikey.controller.check_descriptors', [], cb)
    }

    function checkReaders(filter, cb) {
        doCall('yubikey.controller.check_readers', [filter], cb)
    }

    function setMode(connections, cb) {
        doCall('yubikey.controller.set_mode', [connections], cb)
    }

    function clearCurrentDeviceAndEntries() {
        currentDevice = null
        clearOathEntries()
    }

    function clearOathEntries() {
        entries.clear()
        nextCalculateAll = -1
        currentDeviceValidated = false
    }

    function refreshReaders() {
        yubiKey.getConnectedReaders(function(resp) {
            if (resp.success) {
                availableReaders = resp.readers
            } else {
                console.log("failed to update readers:", resp.error_id)
            }
        })
    }

    function connectToCustomReader() {
        if (settings.useCustomReader) {
            yubiKey.connectCustomReader(settings.customReaderName, function(removed, back, resp) {
                if (removed) {
                    deviceRemoved = true
                } else if (back) {
                    deviceBack = true
                }
            })
        }
    }

    function refreshCurrentDevice(cb) {
        var currentPinCache = !!yubiKey.currentDevice.fidoPinCache ? yubiKey.currentDevice.fidoPinCache : null
        pinIsBlocked = false
        if (settings.useCustomReader) {
            yubiKey.loadDevicesCustomReader(settings.customReaderName, function(resp) {
                if (resp.success) {

                    availableDevices = resp.devices

                    // the same one but potentially updated
                    currentDevice = resp.devices.find(dev => dev.serial === currentDevice.serial)
                    if (currentPinCache) {
                        currentDevice.fidoPinCache = currentPinCache
                    }

                } else {
                    console.log("refreshing devices failed:", resp.error_id)
                    availableDevices = []
                    clearCurrentDeviceAndEntries()

                }

                if (cb) {
                    cb()
                }

            })
        } else {
            yubiKey.loadDevicesUsb(settings.otpMode, function (resp) {
                if (resp.success) {
                    availableDevices = resp.devices

                    // the same one but potentially updated
                    currentDevice = resp.devices.find(dev => dev.serial === currentDevice.serial)
                    if (currentPinCache) {
                        currentDevice.fidoPinCache = currentPinCache
                    }

                } else {
                    console.log("refreshing devices failed:", resp.error_id)
                    availableDevices = []
                    clearCurrentDeviceAndEntries()
                }

                if (cb) {
                    cb()
                }
            })
        }
    }


    function loadDevicesCustomReaderOuter(cb) {
        yubiKey.loadDevicesCustomReader(settings.customReaderName, function(resp) {
            if (resp.success) {
                availableDevices = resp.devices

                if (availableDevices.length === 0) {
                    clearCurrentDeviceAndEntries()
                }

                // no current device, or current device is no longer available, pick a new one
                if (!currentDevice || !availableDevices.some(dev => dev.serial === currentDevice.serial)) {
                    // new device is being loaded, clear any old device
                    clearCurrentDeviceAndEntries()
                    // Just pick the first device
                    currentDevice = availableDevices[0]
                    if(!!currentDevice) {
                        if (yubiKey.currentDeviceEnabled("OATH")) {
                            // If oath is enabled, do a calculate all
                            if (navigator.isInAuthenticator()) {
                                oathCalculateAllOuter()
                            }
                        } else if (navigator.isInAuthenticator()) {
                            navigator.goToYubiKey()
                        }
                    }
                } else {
                    // the same one but potentially updated
                    currentDevice = resp.devices.find(dev => dev.serial === currentDevice.serial)
                }
            } else {
                console.log("refreshing devices failed:", resp.error_id)
                availableDevices = []
                clearCurrentDeviceAndEntries()
            }

            if (cb) {
                cb()
            }

        })
    }

    function loadDevicesUsbOuter(cb) {

        yubiKey.loadDevicesUsb(settings.otpMode, function (resp) {
            if (resp.success) {
                availableDevices = resp.devices

                if (availableDevices.length === 0) {
                    clearCurrentDeviceAndEntries()
                }
                if (resp.noAccess) {
                    if (resp.winFido) {
                        navigator.snackBarError(navigator.getErrorMessage('open_win_fido'))
                    } else {
                        navigator.snackBarError(navigator.getErrorMessage('open_device_failed'))
                    }
                }

                // no current device, or current device is no longer available, pick a new one
                if (!currentDevice || !availableDevices.some(dev => dev.serial === currentDevice.serial)) {
                    // new device is being loaded, clear any old device
                    clearCurrentDeviceAndEntries()
                    // Just pick the first device
                    currentDevice = availableDevices[0]

                    if(!!currentDevice) {
                        if (yubiKey.currentDeviceEnabled("OATH")) {
                            // If oath is enabled, do a calculate all and go to authenticator
                            if (navigator.isInAuthenticator()) {
                                navigator.goToLoading()
                                navigator.goToAuthenticator()
                            }
                        } else if (navigator.isInAuthenticator()) {
                            navigator.goToYubiKey()
                        }
                    }
                } else {
                    // the same one but potentially updated
                    currentDevice = resp.devices.find(dev => dev.serial === currentDevice.serial)
                }
            } else {
                console.log("refreshing devices failed:", resp.error_id)
                availableDevices = []
                clearCurrentDeviceAndEntries()
            }

            if (cb) {
                cb()
            }
        })
    }

    function pollCustomReader() {
        checkReaders(settings.customReaderName, function (resp) {
            if (resp.success) {
                if (resp.needToRefresh) {
                    poller.running = false
                    loadDevicesCustomReaderOuter(function() {
                        poller.running = true
                    })
                } else {
                    // Nothing changed
               }
            } else {
                console.log("check descriptors failed:", resp.error_id)
                clearCurrentDeviceAndEntries()
            }
        })
        refreshReaders()
    }

    function pollUsb() {
	if (isPolling) return
        isPolling = true
        checkUsbDescriptorsChanged(function (resp) {
            if (resp.success) {
                if (resp.usbDescriptorsChanged) {
                    poller.running = false
                    loadDevicesUsbOuter(function() {
                        poller.running = true
                    })
                } else {
                    // Nothing changed
                }

            } else {
                console.log("check descriptors failed:", resp.error_id)
                clearCurrentDeviceAndEntries()
            }
            isPolling = false
        })
    }

    function oathCalculateAllOuter(cb) {
        function callback(resp) {

            if (resp.success) {
                entries.updateEntries(resp.entries, function() {
                    updateNextCalculateAll()
                    currentDeviceValidated = true
                    if (cb) {
                        cb()
                    }
                })
            } else {
                if (resp.error_id === 'access_denied') {
                    entries.clear()
                    currentDevice.hasPassword = true
                    currentDeviceValidated = false
                    navigator.goToEnterPassword()
                } else {
                    clearOathEntries()
                    console.log("calculateAll failed:", resp.error_id)
                }
            }
        }
        if (settings.otpMode) {
            otpCalculateAll(callback)
        } else {
            oathCalculateAll(function (resp) {
                if (resp.success) {
                    entries.updateEntries(resp.entries, function() {
                        updateNextCalculateAll()
                        if (cb) {
                            cb()
                        }
                    })
                } else {
                    if (resp.error_id === 'access_denied') {
                        entries.clear()
                        currentDevice.hasPassword = true
                        navigator.goToEnterPassword()
                        return
                    } else if (resp.error_id === 'no_device_custom_reader') {
                        navigator.snackBarError(navigator.getErrorMessage(resp.error_id))
                        clearCurrentDeviceAndEntries()
                        if (cb) {
                            cb()
                        }
                    } else {
                        clearOathEntries()
                        console.log("calculateAll failed:", resp.error_id)
                        if (!settings.useCustomReader) {
                            loadDevicesUsbOuter()
                        }
                        if (cb) {
                            cb()
                        }
                    }
                }

            })
        }
    }

    function otpCalculate(credential, cb) {
        var margin = credential.touch ? 10 : 0
        var nowAndMargin = Utils.getNow() + margin
        var slot = (credential.key === "Slot 1") ? 1 : 2
        var digits = (slot === 1) ? settings.slot1digits : settings.slot2digits
        doCall('yubikey.controller.otp_calculate',
               [slot, digits, credential, nowAndMargin], cb)
    }

    function otpDeleteCredential(credential, cb) {
        var slot = (credential.key === "Slot 1") ? 1 : 2
        doCall('yubikey.controller.otp_delete_credential', [slot], cb)
    }

    function otpAddCredential(slot, key, touch, cb) {
        doCall('yubikey.controller.otp_add_credential', [slot, key, touch], cb)
    }

    function otpCalculateAll(cb) {
        var now = Utils.getNow()
        doCall('yubikey.controller.otp_calculate_all',
               [settings.slot1digits, settings.slot2digits, now], cb)
    }

    function updateNextCalculateAll() {
        // Next calculateAll should be when a default TOTP cred expires.
        for (var i = 0; i < entries.count; i++) {
            var entry = entries.get(i)
            if (entry.code && entry.credential.period === 30) {
                // Just use the first default one
                nextCalculateAll = entry.code.valid_to
                return
            }
        }
        // No default TOTP cred found, don't set a time for nextCalculateAll
        nextCalculateAll = -1
    }

    function timeToCalculateAll() {
        return nextCalculateAll !== -1 && nextCalculateAll <= Utils.getNow()
    }

    function supportsTouchCredentials() {
        return !!currentDevice && !!currentDevice.version && parseInt(
                    currentDevice.version.split('.').join("")) >= 426
    }

    function supportsOathSha512() {
        return !!currentDevice && !!currentDevice.version && parseInt(
                    currentDevice.version.split('.').join("")) >= 431
                && !isYubiKeyFIPS(currentDevice)
    }

    function scanQr(url) {
        url = !!url ? url : ScreenShot.capture("")
        parseQr(url, function (resp) {
            if (resp.success) {
                navigator.goToNewCredentialScan(resp)
            } else {
                if (resp.error_id === "failed_to_parse_uri") {
                    navigator.confirm({
                        "heading": qsTr("No QR code found"),
                        "description": qsTr("To add an account follow the instructions provided by the service. Make sure the QR code is fully visible before scanning."),
                        "warning": false,
                        "noicon": true,
                        "buttonAccept": qsTr("Try again"),
                        "acceptedCb": function() {
                            yubiKey.scanQr()
                        }
                    })
                } else {
                    navigator.snackBarError(navigator.getErrorMessage(resp.error_id))
                }
            }
        })
    }

    function oathCalculateAll(cb) {
        var now = Math.floor(Date.now() / 1000)
        doCall('yubikey.controller.ccid_calculate_all', [now], cb)
    }

    function loadDevicesCustomReader(customReaderName, cb) {
        doCall('yubikey.controller.load_devices_custom_reader', [customReaderName],  cb)
    }

    function connectCustomReader(customReaderName, cb) {
        setHandler("fido_reset", cb)
        doCall('yubikey.controller.connect_custom_reader', [customReaderName])
    }

    function loadDevicesUsb(otp, cb) {
        doCall('yubikey.controller.load_devices_usb', [otp],  cb)
    }

    function writeConfig(usbApplications, nfcApplications, cb) {
        doCall('yubikey.controller.write_config',
               [usbApplications, nfcApplications], cb) // TODO: lockcode
    }

    function selectCurrentSerial(serial, cb) {
        doCall('yubikey.controller.select_current_serial', [serial], cb)
    }

    function calculate(credential, cb) {
        var margin = credential.touch ? 10 : 0
        var nowAndMargin = Utils.getNow() + margin
        doCall('yubikey.controller.ccid_calculate',
               [credential, nowAndMargin], cb)
    }


    function ccidAddCredential(name, key, issuer, oathType, algo, digits, period, touch, overwrite, cb) {
        doCall('yubikey.controller.ccid_add_credential',
               [name, key, issuer, oathType, algo, digits, period, touch, overwrite], cb)
    }

    function deleteCredential(credential, cb) {
        doCall('yubikey.controller.ccid_delete_credential', [credential], cb)
    }

    function parseQr(data, cb) {
        doCall('yubikey.controller.parse_qr', [data], cb)
    }

    function reset(cb) {
        doCall('yubikey.controller.ccid_reset', [], cb)
    }

    function otpSlotStatus(cb) {
        doCall('yubikey.controller.otp_slot_status', [], cb)
    }

    function setPassword(password, remember, cb) {
        doCall('yubikey.controller.ccid_set_password', [password, remember], cb)
    }

    function removePassword(cb) {
        doCall('yubikey.controller.ccid_remove_password', [], cb)
    }

    function clearLocalPasswords(cb) {
        doCall('yubikey.controller.ccid_clear_local_passwords', [], cb)
    }


    function validate(password, remember, cb) {
        doCall('yubikey.controller.ccid_validate', [password, remember], cb)
    }

    function getConnectedReaders(cb) {
        doCall('yubikey.controller.get_connected_readers', [], cb)
    }

    function fidoSetPin(newPin, cb) {
        doCall('yubikey.controller.fido_set_pin', [newPin], cb)
    }

    function fidoChangePin(currentPin, newPin, cb) {
        doCall('yubikey.controller.fido_change_pin', [currentPin, newPin], cb)
    }

    function fidoVerifyPin(pin, cb) {
        doCall('yubikey.controller.fido_verify_pin', [pin], cb)
    }

    function fidoReset(cb) {
        doCall('yubikey.controller.fido_reset', [], cb)
    }

    function credDelete(userId, cb) {
        doCall('yubikey.controller.fido_cred_delete', [userId], cb)
    }

    function bioEnroll(cb) {
        setHandler("bio_enroll", cb)
        doCall('yubikey.controller.bio_enroll', [])
    }

    function bioEnrollCancel(cb) {
        doCall('yubikey.controller.bio_enroll_cancel', [], cb)
    }

    function bioDelete(template_id, cb) {
        doCall('yubikey.controller.bio_delete', [template_id], cb)
    }

    function bioRename(template_id, name, cb) {
        doCall('yubikey.controller.bio_rename', [template_id, name], cb)
    }

    function bioVerifyPin(pin, cb){
        doCall('yubikey.controller.bio_verify_pin', [pin], cb)
    }

    function resetCancel(cb) {
        doCall('yubikey.controller.reset_cancel', [], cb)
    }
}
