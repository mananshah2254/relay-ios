# Development data handling

This describes the initial implementation. It is not a finished legal privacy policy for a public operator.

## On the phone

The device's service-session token is stored in a shared Keychain access group using after-first-unlock, this-device-only protection. Nonsecret service settings use App Group preferences. Pending share files contain the URL/text, timestamp, destination, and a one-way token fingerprint; they contain no Google or Hunter secret. A file per share avoids conflicting app/extension queue updates. Successful acknowledgement removes the pending file.

Changing the service or device session does not automatically transfer old pending imports to that connection. OAuth access and refresh tokens remain on the service. The custom URL used to return from the Google browser flow contains no bearer credential.

## On the service

The development service stores account settings, job details, recipient contacts, message snapshots, resume bytes, OAuth grants, and the Hunter key in an AES-256-GCM encrypted state file. The encryption key is supplied through the environment, separately from the data directory. The state file is replaced atomically and belongs to one server process. The deployment operator must protect the environment, persistent disk, and backups.

The normal state response contains resume metadata and connection status, not PDF bytes or provider credentials. The server does not read Gmail's inbox; it uses only identity and sending authorization. Reply and bounce monitoring are not included.

## External services

- Google receives sign-in requests and the rendered email plus optional PDF; recipients receive those messages.
- Hunter receives company/domain and contact-search criteria under the supplied Hunter account.
- Supported employer posting APIs receive job-identification requests.
- The implementation includes no third-party AI processor, advertising SDK, open-tracking pixel, or analytics SDK.

Imported text is data, not permission to change settings or send to addresses embedded in the job description. User templates and the selected recipient rules determine preparation.

## Deletion and limits

The app provides account deletion and provider disconnection controls. A sent email cannot be recalled by deleting app data. A Gmail request already in flight may complete even if the user cancels remaining work. Google connection revocation is attempted; users can also remove the app's authorization in Google Account settings.

Resume versions included in already-prepared campaigns remain part of those campaign snapshots until account deletion. Deleting or replacing the default resume affects future preparation. A public release needs a published retention policy, recovery procedures, and any applicable data-subject processes that match the actual hosting setup.
