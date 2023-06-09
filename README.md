# Helpscout Ruby Api.

Download conversations and relative threads from a Help Scout mailbox.

The following files/directories will be created:

* `conversations.csv` A csv file containing conversations data.
* `conversations` A directory containing sub-directories each containing JSON files containing threads data belongs to a specific conversation.

```bash
HelpScoutConversationDownloader.new(app_id, app_secret, mailbox_id)
```


