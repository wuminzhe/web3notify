# scale_rb's websocket client demo

## Usage

### Use with 'socketry/async-io'

```bash
ruby main_async.rb
```

### Use with 'faye/faye-websocket-ruby'

```bash
ruby main_faye.rb
```

## Problems

1. Unable to load the EventMachine C extension;

   if you use FayeClient, you may encounter this error.

   > For people on macOS with OpenSSL installed via Homebrew:
   >   Uninstall eventmachine gem uninstall eventmachine --force
   >   Find the location of OpenSSL with brew info openssl.
   >   Use that location when installing eventmachine. In my case gem install eventmachine --platform ruby -- --user-system-libraries --with-ssl-dir=/opt/homebrew/opt/openssl@3

   https://github.com/eventmachine/eventmachine/issues/820#issuecomment-1211775224
