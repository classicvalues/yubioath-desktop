import QtQuick 2.9

SortedListModel {

    compareFunc: compareFunction
    onDataChanged: sort()
    dynamicRoles: true

    function compareFunction(a, b) {

        function getSortableName(credential) {
            return (credential.issuer
                    || '') + (credential.name
                              || '') + '/' + (credential.period || '')
        }

        return getSortableName(a.credential).localeCompare(getSortableName(
                                                               b.credential))
    }

    function updateEntry(entry) {
        for (var j = 0; j < count; j++) {
            if (get(j).credential.key === entry.credential.key) {
                set(j, entry)
                return
            }
        }
        append(entry)
    }

    function updateEntries(entries) {
        // Update new ones
        for (var i = 0; i < entries.length; i++) {
            updateEntry(entries[i])
        }
        // TODO: clear out deleted ones ?
    }

    function deleteEntry(key) {
        for (var j = 0; j < count; j++) {
            if (get(j).credential.key === key) {
                remove(j)
                return
            }
        }
    }

    function clearCode(key) {
        for (var j = 0; j < count; j++) {
            if (get(j).credential.key === key) {
                setProperty(j, "code", null)
            }
        }
    }
}
