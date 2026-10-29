# M-Pesa automatic prompts: collecting the care plans by themselves

Every local client signs with a care plan paid monthly (by the 7th), weekly (every Monday) or daily (by 21:00). Today
they pay by hand to Paybill 522522, account 1330986040, and the founder chases them. This page is the plan for M-Pesa
to ask them, and pay us, by itself. Nothing here is built yet; the founder decides the two items marked **Founder**.

## The one blocker first: our own shortcode

Paybill 522522 is KCB's shortcode; account 1330986040 is our account behind it. Safaricom's APIs (M-Pesa Express,
standing orders, payment confirmations) are attached to the **owner** of a shortcode, so we cannot use them on
KCB's. Automatic prompts need a shortcode in the company's own name:

- **Lipa na M-Pesa Till (Buy Goods)**, or a **Paybill**, registered to Naim Automation Systems Co. with Safaricom
  (settling into the KCB account if the founder wants), then
- a Daraja app with *M-Pesa Express* (and later *M-Pesa Ratiba*), tested in the sandbox and taken live.

**Founder:** apply for the company Till or Paybill (business registration documents, KRA PIN, the director's ID, the
bank letter). Everything below is built and tested in the Daraja sandbox meanwhile, so it switches on the day the
shortcode goes live.

## Two ways M-Pesa can collect

| | 1. Scheduled prompt (M-Pesa Express / STK Push) | 2. Standing order (M-Pesa Ratiba) |
|---|---|---|
| What the client sees | On each due day, an M-Pesa PIN prompt on their phone: "Pay KES 500 to Naim Automation Systems". One PIN, paid. | Once: a PIN prompt to approve the standing order. After that M-Pesa pays every day, week or month by itself until the end date. |
| Who starts each payment | Our server, on the schedule | M-Pesa itself |
| If they ignore it | Nothing is paid; we prompt again later and send a WhatsApp reminder | Paid automatically while the balance allows; a failed run comes back in the callback |
| Safaricom approval | The standard M-Pesa Express go-live | A **commercial** API: after sandbox testing, email apisupport@safaricom.co.ke; Safaricom discusses terms, signs a contract and links Ratiba to our shortcode |
| Fits | every client, from day one of the shortcode | clients who want "set and forget", once Safaricom approves us |

**Recommendation:** start with scheduled prompts for everyone; offer the standing order to clients who ask for it, once
Ratiba is approved. A client always chooses: prompts on, prompts off (pay by hand), or standing order.

## 1. Scheduled prompts (build first)

**When.** One Netlify scheduled function, `care-billing`, runs every 30 minutes and does only what is due:

| Cycle | First prompt | Again if unpaid | Then |
|---|---|---|---|
| Monthly (due by the 7th) | the 1st, 10:00 | the 4th and the 7th, 10:00 | the late-payment ladder in the agreement (reminder day 3, assistant pauses day 14, read-only day 30) |
| Weekly (due Monday) | Monday 10:00 | Monday 18:00, Tuesday 10:00 | the same ladder, counted from Monday |
| Daily (due by 21:00) | 18:00 | 20:30 | the next day's prompt carries only that day; unpaid days add up and show in NAIM COMMAND |

Never before 08:00 or after 21:00, never twice within 3 hours, never while a prompt is still pending (an unanswered
prompt expires within a couple of minutes), and never after the client switched prompts off.

**How (Daraja M-Pesa Express).** `POST /mpesa/stkpush/v1/processrequest` with `BusinessShortCode`, `Password`
(base64 of shortcode + passkey + timestamp), `Timestamp`, `TransactionType` (`CustomerPayBillOnline` for a Paybill,
`CustomerBuyGoodsOnline` for a Till), `Amount` (whole shillings), `PartyA` and `PhoneNumber` (the client's number,
`2547…`), `PartyB` (the receiving shortcode or till), `CallBackURL` (with a secret path token), `AccountReference`
(the agreement number, at most 12 characters, e.g. `NAS0007`) and `TransactionDesc` (at most 13, e.g. `Care plan`).
The callback (result code 0 = paid) marks the invoice paid and stores the M-Pesa receipt number; anything else
(cancelled, timeout, insufficient funds) is recorded and the next attempt waits for the table above. For a Till,
confirm in the sandbox which number goes in `BusinessShortCode` (the store number) and which in `PartyB` (the till),
and write the answer here.

**What the client gets.** After a paid prompt: a WhatsApp receipt with the invoice. After an unpaid one: a short,
polite reminder drafted for the founder's OK (the same outbox rule as the client systems).

## 2. Standing orders (after Safaricom approves Ratiba)

`POST /standingorder/v1/createStandingOrderExternal` with `StandingOrderName` (unique per customer, e.g.
`Naim care NAS0007`), `StartDate` and `EndDate` (`yyyymmdd`: the first due date, and 12 months later, because the plan's
price is fixed for 12 months), `BusinessShortCode`, `TransactionType` (`Standing Order Customer Pay Bill` or
`Standing Order Customer Pay Marchant`, spelled as Safaricom spells it), `ReceiverPartyIdentifierType` (`4` Paybill,
`2` Till), `Amount` (whole shillings), `PartyA` (the client's `2547…` number), `CallBackURL`, `AccountReference` (max
12), `TransactionDesc` (max 13) and `Frequency`: **2 daily, 3 weekly, 4 monthly** (1 one-off, 5 bi-monthly,
6 quarterly, 7 half-yearly, 8 yearly). The client approves once with their PIN; the callback returns the standing
order's transaction id and status. Each run then arrives as an ordinary payment to our shortcode, matched by the
account reference (confirm in the sandbox that runs reach our confirmation URL, and record it here). A plan change on
the 1st means ending the old order and creating a new one.

## In NAIM COMMAND (Get paid → Care plans)

One row per client: plan, cycle, amount, next due, paid or late, and the mode (**Prompts**, **By hand**, **Standing
order**). Buttons: *Send the M-Pesa prompt now*, *Pause prompts*, *Set up a standing order* (shown once Ratiba is
live). Every prompt and every payment appears in the client's timeline and the activity feed; a payment rings the
office like the other money events.

## Data (migration 010, for the founder to run when we build this)

```sql
-- care plans as signed (cycle month|week|day) and how each is collected
alter table public.subscriptions
  add column if not exists cycle text check (cycle in ('month','week','day')),
  add column if not exists contract_id uuid references public.contracts(id) on delete set null,
  add column if not exists phone text,                                  -- 2547XXXXXXXX, the number that pays
  add column if not exists collect text not null default 'manual' check (collect in ('manual','prompt','standing_order'));

create table if not exists public.mpesa_requests (                     -- every prompt and standing-order request
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid references public.subscriptions(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  kind text not null check (kind in ('stk','ratiba')),
  checkout_id text unique,                                              -- CheckoutRequestID or responseRefID
  phone text not null, amount_kes integer not null check (amount_kes > 0),
  status text not null default 'pending' check (status in ('pending','paid','approved','failed','cancelled','timeout')),
  result_code text, result_desc text, mpesa_receipt text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.mpesa_requests enable row level security;          -- owner/admin read; only Functions write
create policy mpesa_requests_staff_read on public.mpesa_requests for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('owner','admin')));
```

## Secrets and safety

`MPESA_CONSUMER_KEY`, `MPESA_CONSUMER_SECRET`, `MPESA_PASSKEY`, `MPESA_SHORTCODE` and the callback token live only in
the office site's Netlify Function environment. Callbacks are trusted only when their `CheckoutRequestID` (or
reference id) matches a pending request we made, with the same amount; they are idempotent (a second identical
callback changes nothing). No PIN, no full card or account number is ever stored.

**Founder:** one line in the local agreements once this exists, for example: "If you choose automatic prompts, we send
an M-Pesa prompt on each due date and you approve it with your PIN; you can switch them off at any time on WhatsApp."
Legal wording is his call.

## Sources (checked 29 October 2026)

- M-Pesa Ratiba API (Daraja documentation mirror: endpoint, parameters, frequencies, approval by PIN, commercial
  go-live through apisupport@safaricom.co.ke):
  https://glama.ai/mcp/servers/@JacksCodeVault/mpesa-daraja-mcp/blob/e875f3b350a0119c928c623c4e0cdd8999a5d329/daraja_docs_v3/docs/MpesaRatiba.md
- Safaricom, M-PESA Ratiba FAQ: https://safaricom.co.ke/media-center-landing/frequently-asked-questions/m-pesa-ratiba
- Standing orders launch, TechCabal (12 October 2023): https://techcabal.com/2023/10/12/m-pesa-standing-orders-launch/
- STK Push transaction types for tills and paybills: https://www.mctaba.com/kb/stk-push-explained
