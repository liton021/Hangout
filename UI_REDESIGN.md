# UI Redesign — "Midnight Messenger"

The Flutter app now implements the approved dark UI designs. Logic (Firebase
auth, Firestore chat, Agora calling, push) is unchanged — only presentation,
plus one small data addition for unread badges.

## Design system

`lib/theme/app_theme.dart` is the single source of truth.

| Token | Value | Used for |
| --- | --- | --- |
| `canvas` | `#0A0A0C` | screen background |
| `canvasElevated` | `#101013` | bottom nav, composer bar |
| `surface` | `#1A1A1F` | cards, list groups, incoming bubbles |
| `surfaceAlt` | `#232329` | search field, "Online" chip |
| `surfaceMuted` | `#2C2C33` | initial avatars, idle buttons |
| `divider` | `#2A2A31` | hairlines |
| `accent` | `#3B82F6` | active nav pill, FAB, send, unread badge, outgoing bubbles |
| `accentSoft` | `#A9C3FB` | screen titles, A–Z letters, links, Connect button |
| `textPrimary` / `textSecondary` | `#F3F4F6` / `#9CA3AF` | copy |
| `success` / `danger` | `#22C55E` / `#EF4444` | presence / destructive |

Radii live in `AppRadius` (sm 12 · md 16 · lg 20 · xl 28 · pill).
Dark is the default theme mode; a light variant is derived from the same
palette and can still be chosen in Settings → Appearance.

## Screens

| Design | Implementation |
| --- | --- |
| Chats list | `screens/home/chats_tab.dart` |
| Contacts | `screens/home/contacts_tab.dart` |
| Discovery / Find people | `screens/home/discovery_tab.dart` |
| Settings | `screens/settings/settings_screen.dart` |
| Conversation | `screens/chat/chat_screen.dart` |
| Shell + bottom nav | `screens/home/home_screen.dart`, `widgets/bottom_nav.dart` |

Shared building blocks: `widgets/app_header.dart` (header, section header,
group card, overline), `widgets/search_field.dart`, `widgets/avatar.dart`,
`widgets/states.dart`, `utils/contact_actions.dart`.

## Decisions worth knowing

* **Calls is no longer a tab.** The design has exactly four tabs (Chats,
  Contacts, Discovery, Settings), so call history moved to
  **Settings → Call history** (`screens/home/calls_screen.dart`). Calling
  itself is unchanged and still reachable from a conversation header, a
  contact long-press and the call log.
* **Unread badges are real.** `ChatService.unreadCountStream` feeds the blue
  badge and `ChatService.markMessagesRead` clears it when a chat is opened —
  which also makes the existing read receipts (double ticks) work.
* **Discovery data.** "Suggested for You" lists real Hangout users, ordered so
  people you have no chat with come first; the button reads **Connect** for
  them and **Message** for existing conversations. "Trending Channels" reads an
  optional Firestore `channels` collection
  (`{ name, members, online, icon }`); while that collection is empty the
  section shows a placeholder card instead of fake data.
* **Long-press anywhere** on a person (chat row, contact, frequent card, call
  log) opens Message / Voice call / Video call.
* Rows that the design shows but the backend doesn't support yet (Privacy,
  Notifications, Data & Storage) are styled exactly as designed and show a
  "coming soon" snackbar; Account opens a profile sheet and Help opens the
  about dialog.
