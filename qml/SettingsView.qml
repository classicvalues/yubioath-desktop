import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
import QtGraphicalEffects 1.0

ScrollView {

    readonly property int dynamicWidth: 864
    readonly property int dynamicMargin: 32

    id: settingsPanel
    objectName: 'settingsView'
    contentWidth: app.width

    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ScrollBar.vertical.width: 8

    Keys.onEscapePressed: navigator.home()

    function getDeviceLabel(device) {
        if (!!device.serial) {
            return ("%1 (#%2)").arg(device.name).arg(device.serial)
        }  else {
            return ("%1").arg(device.name)
        }
    }

    function getDeviceDescription() {
        if (!!yubiKey.currentDevice) {
            return yubiKey.currentDevice.usbInterfacesEnabled.join('+')
        } else if (yubiKey.availableDevices.length > 0
                   && !yubiKey.availableDevices.some(dev => dev.selectable)) {
            return "No compatible device found"
        } else {
            return "No device found"
        }
    }


    function clearPasswordFields() {
        currentPasswordField.text = ""
        newPasswordField.text = ""
        confirmPasswordField.text = ""
    }

    function submitPassword() {
        if (acceptableInput()) {
            if (yubiKey.currentDeviceHasPassword) {
                changePassword()
            } else {
                setPassword()
            }
        }
    }

    function acceptableInput() {
        if (yubiKey.currentDeviceValidated) {
            if (yubiKey.currentDeviceHasPassword
                    && currentPasswordField.text.length == 0) {
                return false
            }
            if (newPasswordField.text.length > 0
                    && (newPasswordField.text === confirmPasswordField.text)) {
                return true
            }
        }
        return false
    }

    function changePassword() {
        yubiKey.validate(currentPasswordField.text, false, function (resp) {
            if (resp.success) {
                setPassword()
            } else {
                navigator.snackBarError(getErrorMessage(resp.error_id))
                console.log("change password failed:", resp.error_id)
            }
            clearPasswordFields()
        })
    }

    function setPassword() {
        yubiKey.setPassword(newPasswordField.text, false, function (resp) {
            if (resp.success) {
                navigator.snackBar("Password set")
                yubiKey.currentDeviceHasPassword = true
                passwordManagementPanel.isExpanded = false
            } else {
                navigator.snackBarError(getErrorMessage(resp.error_id))
                console.log("set password failed:", resp.error_id)
            }
            clearPasswordFields()
        })
    }

    function removePassword() {
        yubiKey.validate(currentPasswordField.text, false, function (resp) {
            if (resp.success) {
                // TODO: Change to new method that works
                yubiKey.setPassword(null, true, function (resp) {
                    if (resp.success) {
                        navigator.snackBar("Password removed")
                        yubiKey.currentDeviceHasPassword = false
                        passwordManagementPanel.isExpanded = false
                    } else {
                        navigator.snackBarError(getErrorMessage(resp.error_id))
                        console.log("remove password failed:", resp.error_id)
                    }
                    clearPasswordFields()
                })
            } else {
                navigator.snackBarError(getErrorMessage(resp.error_id))
                console.log("remove password failed:", resp.error_id)
            }
        })
    }

    property string title: "Settings"

    ListModel {
        id: themes

        ListElement {
            text: "System Default"
            value: Material.System
        }
        ListElement {
            text: "Light Mode"
            value: Material.Light
        }
        ListElement {
            text: "Dark Mode"
            value: Material.Dark
        }
    }

    ListModel {
        id: themeColor

        ListElement {
            text: "Green"
            value: "#9aca3c"
        }
        ListElement {
            text: "Blue"
            value: "#284c61"
        }
        ListElement {
            text: "Red"
            value: "#fd5552"
        }
        ListElement {
            text: "Grey"
            value: "#939598"
        }
    }

    ListModel {
        id: otpModeDigits

        ListElement {
            text: "Off"
            value: 0
        }
        ListElement {
            text: "6"
            value: 6
        }
        ListElement {
            text: "7"
            value: 7
        }
        ListElement {
            text: "8"
            value: 8
        }
    }

    spacing: 8
    padding: 0

    ColumnLayout {
        id: content
        anchors.fill: parent
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 0

        StyledExpansionContainer {
            id: keyPane
            sectionTitle: "Device"

            StyledExpansionPanel {
                id: currentDevicePanel
                label: !!yubiKey.currentDevice ? getDeviceLabel(yubiKey.currentDevice) : "Insert your YubiKey"
                description: getDeviceDescription()
                keyImage: yubiKey.getCurrentDeviceImage()
                isTopPanel: true
                Layout.fillWidth: true
                isEnabled: yubiKey.availableDevices.length > 1

                ButtonGroup {
                    id: deviceButtonGroup
                }

                ColumnLayout {
                    Layout.fillWidth: true

                    Repeater {
                        model: yubiKey.availableDevices
                        RadioButton {
                            Layout.fillWidth: true
                            objectName: index
                            checked: !!yubiKey.currentDevice
                                     && modelData.serial === yubiKey.currentDevice.serial
                            text: getDeviceLabel(modelData)
                            enabled: modelData.selectable
                            ButtonGroup.group: deviceButtonGroup
                        }
                    }

                    StyledButton {
                        id: selectBtn
                        Layout.alignment: Qt.AlignRight | Qt.AlignBottom
                        text: "Select"
                        enabled: {
                            if (!!yubiKey.availableDevices && !!deviceButtonGroup.checkedButton) {
                                var dev = yubiKey.availableDevices[deviceButtonGroup.checkedButton.objectName]
                                return dev !== yubiKey.currentDevice
                            } else {
                                return false
                            }
                        }
                        onClicked: {
                            var dev = yubiKey.availableDevices[deviceButtonGroup.checkedButton.objectName]
                            yubiKey.selectCurrentSerial(dev.serial,
                                                        function (resp) {
                                                            if (resp.success) {
                                                                yubiKey.nextCalculateAll = -1
                                                                entries.clear()
                                                                yubiKey.currentDevice = dev
                                                                currentDevicePanel.expandAction()
                                                            } else {
                                                                console.log("select device failed", resp.error_id)
                                                            }
                                                        })
                        }
                    }
                }
            }
        }

        StyledExpansionContainer {
            id: oathPane
            sectionTitle: "OATH"
            visible: !!yubiKey.currentDevice

            StyledExpansionPanel {
                id: passwordManagementPanel
                label: yubiKey.currentDeviceHasPassword ? "Change Password" : "Set Password"
                description: "For additional security and to prevent unauthorized access the YubiKey may be protected with a password."
                isTopPanel: true

                ColumnLayout {

                    StyledTextField {
                        id: currentPasswordField
                        visible: yubiKey.currentDeviceHasPassword ? true : false
                        labelText: qsTr("Current Password")
                        echoMode: TextInput.Password
                        Keys.onEnterPressed: submitPassword()
                        Keys.onReturnPressed: submitPassword()
                    }
                    StyledTextField {
                        id: newPasswordField
                        labelText: qsTr("New Password")
                        echoMode: TextInput.Password
                        Keys.onEnterPressed: submitPassword()
                        Keys.onReturnPressed: submitPassword()
                    }
                    StyledTextField {
                        id: confirmPasswordField
                        labelText: qsTr("Confirm Password")
                        echoMode: TextInput.Password
                        Keys.onEnterPressed: submitPassword()
                        Keys.onReturnPressed: submitPassword()
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        StyledButton {
                            id: removePasswordBtn
                            visible: yubiKey.currentDeviceHasPassword
                            enabled: currentPasswordField.text.length > 0
                            text: "Remove"
                            flat: true
                            onClicked: navigator.confirm(
                                           "Remove password?",
                                           "A password will not be required to access the credentails anymore.",
                                           function () {
                                               removePassword()
                                           })
                        }
                        StyledButton {
                            id: applyPassword
                            text: yubiKey.currentDeviceHasPassword ? "Change" : "Set"
                            enabled: acceptableInput()
                            onClicked: submitPassword()
                        }
                    }
                }
            }

            StyledExpansionPanel {
                label: "Reset"
                description: "Warning: Resetting the OATH application will delete all credentials and restore factory defaults."
                isEnabled: false
                toolButtonIcon: "../images/reset.svg"
                toolButtonToolTip: "Reset OATH Application"
                toolButton.onClicked: navigator.confirm(
                                          "Reset OATH application?",
                                          "This will delete all credentials and restore factory defaults.",
                                          function () {
                                              navigator.goToLoading()
                                              yubiKey.reset(function (resp) {
                                                  navigator.goToSettings()
                                                  if (resp.success) {
                                                      entries.clear()
                                                      navigator.snackBar(
                                                                  "Reset completed")
                                                      yubiKey.currentDeviceValidated = true
                                                      yubiKey.currentDeviceHasPassword = false
                                                  } else {
                                                      navigator.snackBarError(
                                                                  navigator.getErrorMessage(
                                                                      resp.error_id))
                                                      console.log("reset failed:",
                                                                  resp.error_id)
                                                  }
                                              })
                                          })
            }
        }

        StyledExpansionContainer {
            id: appPane
            sectionTitle: "Application"

            StyledExpansionPanel {
                label: "Appearance"
                description: "Change the theme and appearance of the application."
                isTopPanel: true

                ColumnLayout {

                    RowLayout {
                        Layout.fillWidth: true
                        StyledComboBox {
                            id: themeComboBox
                            label: "Appearance"
                            comboBox.textRole: "text"
                            model: themes
                            onCurrentIndexChanged: {
                                settings.theme = themes.get(currentIndex).value
                            }
                            currentIndex: {
                                switch (settings.theme) {
                                case Material.System:
                                    return 0
                                case Material.Light:
                                    return 1
                                case Material.Dark:
                                    return 2
                                default:
                                    return 0
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        StyledComboBox {
                            id: themeColorComboBox
                            label: "Theme Color"
                            comboBox.textRole: "text"
                            model: themeColor
                            onCurrentIndexChanged: {
                                settings.themeAccentColor = themeColor.get(
                                            currentIndex).value
                            }
                            currentIndex: {
                                for (var i = 0; i < themeColor.count; i++) {
                                    if (themeColor.get(
                                                i).value === settings.themeAccentColor) {
                                        return i
                                    }
                                }
                                return 0
                            }
                        }
                    }
                }
            }

            StyledExpansionPanel {
                id: authenticatorModePanel
                label: "Authenticator Mode"
                description: "Configure how to read credentials from the YubiKey."
                property bool otpModeSelected: authenticatorModeCombobox.currentIndex === 1
                property bool aboutToChange: (otpModeSelected !== settings.otpMode)
                                             || (slot1DigitsComboBox.currentIndex
                                                 !== getComboBoxIndex(
                                                     settings.slot1digits))
                                             || (slot2DigitsComboBox.currentIndex
                                                 !== getComboBoxIndex(
                                                     settings.slot2digits))

                function isValidMode() {
                    return aboutToChange
                            && ((otpModeSelected
                                 && (slot1DigitsComboBox.currentIndex !== 0
                                     || slot2DigitsComboBox.currentIndex !== 0))
                                || !otpModeSelected)
                }

                function setAuthenticatorMode() {

                    function callback() {
                        navigator.goToSettings()
                        navigator.snackBar("Authenticator mode changed")
                    }

                    navigator.goToLoading()
                    settings.slot1digits = otpModeDigits.get(
                                slot1DigitsComboBox.currentIndex).value
                    settings.slot2digits = otpModeDigits.get(
                                slot2DigitsComboBox.currentIndex).value
                    settings.otpMode = otpModeSelected
                    entries.clear()
                    yubiKey.nextCalculateAll = -1
                    if (!!yubiKey.currentDevice) {
                        yubiKey.calculateAll(callback)
                    } else {
                        callback()
                    }
                }

                function getComboBoxIndex(digits) {
                    switch (digits) {
                    case 0:
                        return 0
                    case 6:
                        return 1
                    case 7:
                        return 2
                    case 8:
                        return 3
                    default:
                        return 0
                    }
                }

                ColumnLayout {

                    RowLayout {
                        Layout.fillWidth: true
                        StyledComboBox {
                            id: authenticatorModeCombobox
                            label: "Authenticator Mode"
                            model: ["CCID (recommended)", "OTP"]
                            currentIndex: settings.otpMode ? 1 : 0
                        }
                    }
                }

                RowLayout {
                    visible: authenticatorModeCombobox.currentText.indexOf(
                                 "OTP") > -1
                    Label {
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        color: formLabel
                        text: "Using the OTP slots should be considered for special cases only."
                        wrapMode: Text.WordWrap
                        Layout.rowSpan: 1
                        bottomPadding: 8
                    }
                }

                RowLayout {
                    visible: authenticatorModePanel.otpModeSelected

                    StyledComboBox {
                        id: slot1DigitsComboBox
                        label: "Slot 1 Digits"
                        comboBox.textRole: "text"
                        model: otpModeDigits
                        currentIndex: authenticatorModePanel.getComboBoxIndex(
                                          settings.slot1digits)
                    }

                    Item {
                        width: 16
                    }

                    StyledComboBox {
                        id: slot2DigitsComboBox
                        label: "Slot 2 Digits"
                        comboBox.textRole: "text"
                        model: otpModeDigits
                        currentIndex: authenticatorModePanel.getComboBoxIndex(
                                          settings.slot2digits)
                    }
                }
                StyledButton {
                    Layout.alignment: Qt.AlignRight | Qt.AlignTop
                    text: "Apply"
                    enabled: authenticatorModePanel.isValidMode()
                    onClicked: authenticatorModePanel.setAuthenticatorMode()
                }
            }

            StyledExpansionPanel {
                label: Qt.platform.os === "osx" ? "Menu Bar" : "System Tray"
                description: "Configure where and how the application is visible."
                isBottomPanel: true

                ColumnLayout {
                    CheckBox {
                        id: sysTrayCheckbox
                        checked: settings.closeToTray
                        text: Qt.platform.os === "osx" ? "Show in menu bar" : "Show in system tray"
                        padding: 0
                        indicator.width: 16
                        indicator.height: 16
                        onCheckStateChanged: settings.closeToTray = checked
                        Material.foreground: formText
                    }

                    CheckBox {
                        enabled: sysTrayCheckbox.checked
                        checked: settings.hideOnLaunch
                        text: "Hide on launch"
                        padding: 0
                        indicator.width: 16
                        indicator.height: 16
                        onCheckStateChanged: settings.hideOnLaunch = checked
                        Material.foreground: formText
                    }
                }
            }
        }

        StyledExpansionContainer {
            id: aboutPane
            sectionTitle: "About"

            StyledExpansionPanel {
                id: aboutPanel
                label: qsTr("Yubico Authenticator ") + appVersion
                description: qsTr("Copyright © " + Qt.formatDateTime(
                                      new Date(),
                                      "yyyy") + ", Yubico AB. All rights reserved.")
                isTopPanel: true
                isEnabled: false
            }
        }
    }
}
