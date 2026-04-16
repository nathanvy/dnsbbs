# DNS BBS
This is a minimalist BBS, or maybe a web 2.0-style forum, except it runs entirely over DNS.  I got the idea for it after doing a deep dive into the different covert channel communications techniques used by modern malware.  This BBS is:

- stateless (no sessions)
- anonymous, usenames optional
- append-only
- clunky
- fun!

## Build
This BBS has only been tested on Debian `amd64`.  **Absolutely no thought whatsoever** was given towards compatibility on other architectures or operating systems.  In theory, it should run anywhere Docker and SBCL run.

## wtf
Rationale:  https://0x85.org/dnsbbs.html

Depending on when you read this page, there may be a demo running on `bbs.stackgho.st`.  Try:

```
$ dig @bbs.stackgho.st -p 31337 wtf.bbs.stackgho.st TXT
```

## Topics
A list of topics can be retrieved via:

```
index.bbs.example.org TXT
```

Available topics are returned as a semicolon-separated list.  For example the "dev" and "misc" topics would come back as such:  `t=dev,misc`.  Information about a topic is available via:

```
meta.misc.bbs.example.org TXT
```
This will return the topic description and the id of the most recent message, like so: `desc=General discussion;latest=1`

## Reading messages
Once you have the ID of a message it can be retrieved like so:

```
msg.<id>.<topic>.bbs.example.org TXT
```

Or, for messages too long for a single response that have been chunked:

```
msg.<id>.<page>.<topic>.bbs.example.org TXT
```

Messages are returned base64-encoded (because only leet haxors use base64 of course)

## Posting messages
Posting messages is accomplished by Base32-encoding the message contents. 

```
post.<b32(msg)>.<topic>.bbs.example.org TXT
```

If the message is too long, it must be chunked:

```
post.<b32chunk>.<nonce>.<seq>.<topic>.bbs.example.org TXT
```

In this last query, `<nonce>` is a short client-supplied random string (e.g. a hex string like `a3f9`) that uniquely identifies the posting session. This prevents chunk buffers from colliding when two clients behind the same NAT post simultaneously.  `<seq>` is an integer sequence number beginning at 0 and increasing from there.  The final chunk is signified by passing the string `end` for the sequence number, rather than an integer.


