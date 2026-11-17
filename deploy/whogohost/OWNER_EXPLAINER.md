# Why the ₦8,600 plan can't run the MISPEC API

Plain-language note for the account owner. No jargon needed below the line.

## 1. What we already bought

**WhoGoHost "Python Hosting — Flex", ₦8,600/month.**

What it includes:

- 25 GB SSD storage, 100 GB monthly bandwidth
- 1 GB RAM, 1.5 CPU cores
- DirectAdmin control panel (the dashboard you're looking at)
- Unlimited **MySQL** databases, unlimited email accounts
- Free SSL certificate, Git and SSH access
- A free `.ng` domain when billed annually

It is a good plan. It runs websites, WordPress, PHP apps, email, and **simple** Python sites. Nothing is wasted or mis-sold — it just has limits that matter for this particular app.

## 2. What the MISPEC API needs

The backend is not a website. It is a service with four moving parts that must run all day, every day:

| The API needs | Why |
|---|---|
| **PostgreSQL** database | Already built and tested on it; DirectAdmin only offers MySQL |
| **Redis** | The queue that hands background jobs to workers |
| **Two background workers running 24/7** | Sends emails/OTP, geocoding, daily plan checks, monthly call resets |
| **Root access to the server** | To install and keep those four parts running and restart them automatically |

The Flex plan gives us MySQL instead of PostgreSQL, no Redis, and no way to keep a program running permanently in the background — shared hosting stops long-running processes.

## 3. The simple way to picture it

> Shared hosting is like renting a desk in a shared office. You get a desk, electricity, a receptionist and a post box — perfect for a website.
>
> Our backend is a small factory. It needs its own generator, its own storeroom and machines that run through the night. The office building won't let us install those.
>
> A **VPS** is renting our own small unit in the same building: same landlord (WhoGoHost), same Naira billing, but we control the inside.

## 4. The options, with real numbers

| Option | Monthly cost | What happens |
|---|---|---|
| **A. Keep Flex + add VPS C2** *(recommended)* | ₦8,600 + ₦18,275 = **₦26,875** | Flex keeps our domain, email and website/landing page. The VPS runs the API properly — no code changes, ready-made deployment scripts already written. |
| **B. Keep Flex + add VPS C1** *(budget)* | ₦8,600 + ₦11,050 = **₦19,650** | Same as A but 1 GB RAM. Works for low traffic; may feel slow under load. Can be upgraded to C2 later with no downtime. |
| **C. Force it onto Flex only** | ₦8,600 | Requires rewriting the app: MySQL instead of PostgreSQL, and replacing the always-on workers with scheduled cron jobs. Roughly **2–4 days of development**, plus slower API responses and lost retries. Not recommended. |
| **D. Leave the API on Render, Flex for domain/email/site** | ₦8,600 (Render already running) | No new hosting cost. But the API stays on a foreign platform and the free/small Render tier sleeps when idle, which delays the first request. |
| **E. VPS only, cancel Flex** | ₦18,275 | Cheapest technically, but we lose the email accounts on the domain and the website hosting, and would need to rebuild both elsewhere. |

## 5. What I recommend

**Option A** if the budget allows, **Option B** if it doesn't.

The reason is simply that the app is already finished and working. Options A and B put it on the server with **zero code changes** — the setup, database, background workers and HTTPS are all scripted and ready to run in about an hour. Option C spends days of work to save a few thousand Naira per month, and leaves us with a more fragile system that will break in new ways later.

## 6. The three sentences to send

> The ₦8,600 plan is fine for the website and our email, but it can't run the app's engine — it only allows simple websites, not the database and background processes our API needs. We need to add a small VPS (₦18,275/month) for the API; the ₦8,600 plan stays for the domain, email and landing page. Without it, we'd have to rebuild part of the app and accept slower, less reliable service.

## 7. If the owner asks "can't we just make it work on the ₦8,600?"

Honest answer: yes, but it means changing the product, not just a setting.

1. Move the database from PostgreSQL to MySQL, and test every feature again.
2. Remove the always-on background workers; run their jobs from the control panel's scheduler instead.
3. Accept that emails/OTP and geocoding happen on a delay, with no automatic retries.
4. Still no guarantee the host permits long-running Python processes, so it may be refused after the work is done.

That is why the recommendation is a small VPS: same provider, Naira billing, local support, and the app runs exactly as it was built and tested.
