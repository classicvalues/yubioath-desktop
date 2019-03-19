import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Controls.Material 2.2
import QtGraphicalEffects 1.0

Pane {
    implicitWidth: 360
    implicitHeight: 80

    Material.elevation: 0

    property var entry

    property string issuer: entry.credential.issuer || ''
    property string name: entry.credential.name
    property string code: entry.code ? entry.code.value : ''
    property bool touch: entry.credential.touch

    background: Rectangle {
        color: app.isDark() ? app.defaultDarkLighter : app.defaultLightDarker
    }

    function formattedCode(code) {
        // Add a space in the code for easier reading.
        if (code !== null) {
            switch (code.length) {
            case 6:
                // 123 123
                return code.slice(0, 3) + " " + code.slice(3)
            case 7:
                // 1234 123
                return code.slice(0, 4) + " " + code.slice(4)
            case 8:
                // 1234 1234
                return code.slice(0, 4) + " " + code.slice(4)
            default:
                return code
            }
        }
    }

    Item {
        anchors.fill: parent

        CredentialCardIcon {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            size: 40
            letter: issuer ? issuer.charAt(0) : name.charAt(0)
        }

        ColumnLayout {
            anchors.left: icon.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Label {
                id: issuerLbl
                text: issuer
                visible: issuer
                font.pixelSize: 12
            }
            Label {
                id: codLbl
                font.pixelSize: 24
                color: !touch ? yubicoGreen : yubicoGrey
                text: !touch ? formattedCode(code) : "Requires touch"
                visible: code || touch
            }
            Label {
                id: nameLbl
                text: name
                font.pixelSize: 12
            }
        }

        CredentialCardTimer {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            Layout.alignment: Qt.AlignRight | Qt.AlignBottom
            colorCircle: Material.primary
            visible: !touch
        }

        Image {
            id: touchIcon
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 16
            height: 16
            fillMode: Image.PreserveAspectFit
            source: "../images/touch.png"
            visible: touch
        }
    }
}
