# Audio assets

Drop royalty-free `.mp3` (or `.wav`) files here with these exact filenames.
Missing files are silently ignored — the app keeps working, just no sound for that event.

After adding/removing files run `flutter pub get` so they get bundled.

## Required (most impactful)
- `order_incoming.mp3` — short alert when a new order pops up (~0.5–1.0s)
- `cash.mp3` — payout sound after delivery (~0.6s)
- `level_up.mp3` — fanfare on level-up (~1.0–1.5s)
- `achievement.mp3` — chime on achievement unlock (~1.0s)
- `knock.mp3` — knocking on door (~0.4s; played 3× per delivery)
- `phone_ring.mp3` — phone ringtone when customer doesn't answer (~2–3s)
- `camera_shutter.mp3` — photo proof shutter (~0.3s)
- `chat_ding.mp3` — customer chat message (~0.4s)
- `traffic_light.mp3` — short beep at red light (~0.4s)
- `button_tap.mp3` — accept/confirm button press (~0.1s, very subtle)

## Engine loops (looped while riding)
- `engine_bike.mp3` — bicycle chain/whir, seamless loop (~3–6s)
- `engine_scooter.mp3` — small motor idle, seamless loop (~3–6s)
- `engine_car.mp3` — car engine idle, seamless loop (~3–6s)

## Optional ambient
- `ambient_city.mp3` — distant traffic/crowd, seamless loop (~10–30s, played at low volume while online)

## Where to find free assets
- freesound.org (CC0 / CC-BY)
- pixabay.com/sound-effects
- mixkit.co/free-sound-effects
- zapsplat.com (free with account)

Keep files small (< 200 KB each ideally). For loops, trim to clean zero-crossings to avoid clicks.
