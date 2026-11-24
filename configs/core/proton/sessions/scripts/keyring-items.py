"""Secret Service items as JSON, binary-safe: `load <attributes-json>` prints the matching items, `save` creates the
items read from stdin. secret-tool cannot carry them: it refuses a secret that is not UTF-8 (Proton Authenticator's).
Secrets travel only over stdin and stdout, never argv."""

import base64
import json
import sys

import secretstorage


def items_load(attributes: dict) -> list:
    connection = secretstorage.dbus_init()
    collection = secretstorage.get_default_collection(connection)
    items = [
        {
            "label": item.get_label(),
            "attributes": dict(sorted(item.get_attributes().items())),
            "content_type": item.get_secret_content_type(),
            "secret": base64.b64encode(item.get_secret()).decode("ascii"),
        }
        for item in collection.search_items(attributes)
    ]
    # the search order varies between runs; a stable one keeps an unchanged backup byte-identical
    return sorted(items, key=lambda item: json.dumps(item["attributes"], sort_keys=True))


def items_save(items: list) -> None:
    connection = secretstorage.dbus_init()
    collection = secretstorage.get_default_collection(connection)
    for item in items:
        secret = base64.b64decode(item["secret"])
        collection.create_item(item["label"], item["attributes"], secret, content_type=item["content_type"])


def main() -> None:
    verb = sys.argv[1]
    if verb == "load":
        json.dump(items_load(json.loads(sys.argv[2])), sys.stdout)
    elif verb == "save":
        items_save(json.load(sys.stdin))
    else:
        sys.exit(f"keyring-items: unknown verb {verb}")


main()
