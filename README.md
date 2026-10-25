# MailMaster

> World of Warcraft **3.3.5a (WotLK)** addon · made by **feralpaw** · version **1.3.2**

**Collects mail 10× faster than usual mail addons and up to 30× faster than the server default, and sends in a fraction of the clicks.**
Lightweight: plain Lua, no libraries, windows are only created when you open them.

## Features

### Collecting mail
- **Open All** takes gold and items from all mail. 0.03 s per request by default (adjustable from 0.00 to 1.00 s).
- **Check pass**: after a run, anything the server dropped is picked up again automatically.
- **More than 50 mails**: waits for the server's next batch and carries on by itself, with a countdown in the inbox.
- **Filters** (gear button): AH sold / expired / cancelled / outbid / won, player mail with items, player mail with gold, system / Postmaster mail.
- **Shift-click Open All** takes everything and ignores the filters. CoD and GM mail are never opened.
- **Click Open All again** to stop.
- **Bag protection**: keeps a set number of slots free. When the bags are full it stops taking items but still takes gold.

### Inbox
- **Info line**: number of mails (plus how many are still on the server), gold, items, CoD mails, mail about to expire and gold collected so far.
- **Checkboxes**: open or return only the mail you tick. Shift-click selects a range, Ctrl-click selects all mail from that sender.
- **Red X** on each mail deletes it or returns it to the sender. It asks first when the mail holds gold or items.
- **Shift-click a mail** takes everything in it. **Ctrl-click** returns it.
- **Tooltip**: all attachments, the full subject, and when the mail expires and whether it then gets deleted or returned.
- **Expiry warning**: mail with gold or items that expires within 3 days is shown in orange and announced in chat.
- **Copy**: sender, subject and text of a mail, ready for Ctrl+C.
- **Forward**: forwards a mail with all its items, gold and text. Stacks are rebuilt to the original amounts.
- **Gold collected** is printed when you close the mailbox.
- **Auto return/delete rules** by sender or subject, with a test mode. Only mail without anything of value is ever deleted.

### Sending
- **Alt + move the mouse over your bags** to attach items. **Alt+Shift** attaches every stack of that item. **Ctrl+Alt** over an attachment takes it back out. Works with the default bags, AdiBags, Bagnon and ElvUI bags.
- **Mail full (12/12)**: optionally sends it automatically and keeps the recipient for the next mail.
- **Clear** button: takes all attachments out and resets the gold amount.
- **Contacts panel**: search, favourites, alts (class coloured), recently mailed, friends and guild (online first).
- **Letter icon** next to an alt sends the current mail to that alt straight away.
- **Name completion** from favourites, alts and recent recipients.
- **Quick attach** for 13 categories (cloth, herbs, ore, leather, enchanting, gems, elemental, glyphs, meat, engineering, consumables, recipes, other trade goods). A menu lets you pick everything, one sub type (for example only flasks) or one specific item.
- **Stack splitting** straight into the mail (for example 5 × 20).
- **Send rules** like *herbs → HerbAlt* or *never send item X*. One click sends everything that matches, with a preview first.
- **Wire**: when you send gold, the amount goes into the subject.
- **CoD helper**: suggests a price from AuctionaryPro / Auctionary, Auctionator or the vendor price.
- Blocks trade requests and guild invites while the mailbox is open. Blocking group invites is optional.

### Prepared mail (outbox)
- Prepare mails anywhere: recipient, gold, subject and up to 12 different items (a set amount or "all").
- Drop items on the slots or Alt-slide over your bags.
- Edit or delete prepared mails at any time.
- Everything is sent automatically the next time you open a mailbox. Too much for one mail is split across several.

### Overview & history
- `/mm alts`: mail, gold, items and the next expiry for every character.
- `/mm inbox [name]`: the last seen inbox of any character, from anywhere.
- Login warning when mail with gold or items is about to expire on any character.
- Mail you send to your alts shows up in their overview right away.
- **Mail log** with two tabs: `/mm sent` lists everything you sent, `/mm received` everything you collected (gold and items per mail, which character got it). Searchable. Kept for 10 days by default, or 1, 3, 6 or 12 months, or forever.

### Look & settings
- Its own button style and 14 colour themes (including class colour).
- **Minimap button**: left-click opens prepared mail, Shift-click opens the mail log, right-click opens the options. It can be dragged and hidden.
- Options under *Esc → Interface → AddOns → MailMaster* or `/mm`.
- Shared or per-character settings, with a reset to defaults.

## Commands
| Command | What it does |
|---|---|
| `/mm` | Options |
| `/mm alts` | Mail overview of all your characters |
| `/mm inbox <name>` | Last seen inbox of a character (works anywhere) |
| `/mm queue` | Prepared mail (outbox) |
| `/mm sent` | Mail log: sent mail |
| `/mm received` | Mail log: collected mail |
| `/mm rules` / `/mm rules test` | Run the return/delete rules / only show what they would do |
| `/mm stop` | Stop opening mail |
| `/mm help` | List of commands |

## Installation
1. Download the latest ZIP from **Releases** (or *Code → Download ZIP*).
2. Copy the `MailMaster` folder into `World of Warcraft/Interface/AddOns/`.
   The folder name must stay exactly like this (no `-main` suffix).
3. Disable any other mail addon so they don't fight over the mailbox.
4. Restart the game or type `/reload`.

## License
MIT – see [LICENSE](LICENSE).
