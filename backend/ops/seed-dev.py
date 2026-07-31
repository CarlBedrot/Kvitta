#!/usr/bin/env python3
"""Seed the local dev backend with a lived-in test environment.

Creates fake friends (dev accounts with Swish numbers in their profiles), three groups with
weeks of expenses and payments — one of them mixed SEK/DKK — and links every friend through the
real invite flow, so nothing here bypasses validation: everything goes through the same API the
app uses.

Usage:
    python3 backend/ops/seed-dev.py --user <your-device-user-uuid>

The --user id must be the one the app will dev-sign-in as (`se.kvitta.localUserId` in the app's
UserDefaults). On a simulator:
    xcrun simctl spawn booted defaults read se.kvitta.app se.kvitta.localUserId

Requires the backend running in Development with Auth:AllowDevTokens=true. Safe to re-run: each
run creates fresh groups (the log is append-only; there is deliberately no delete).
"""

import argparse
import datetime
import json
import urllib.request
import uuid

FRIENDS = {
    # name: swish number (profile field, served to co-members)
    "Jonas": "46701111111",
    "Sara": "46702222222",
    "Ellen": "46703333333",
    "Alex": "46704444444",
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="http://localhost:5142")
    parser.add_argument("--user", required=True, help="your device's user UUID")
    args = parser.parse_args()

    api = Api(args.base)
    you = api.sign_in(args.user)
    friends = {name: api.sign_in(str(uuid.uuid4())) for name in FRIENDS}
    for name, session in friends.items():
        api.put_profile(session, FRIENDS[name])

    malmo = Group(api, you, "🏖️ Malmö-gänget", "SEK", ["Jonas", "Sara", "Ellen"], friends)
    malmo.expense("Systembolaget", "alkohol", 43_700, paid_by="Du", days_ago=21)
    malmo.expense("ICA Maxi", "groceries", 61_850, paid_by="Jonas", days_ago=20)
    malmo.expense("Restaurang Lyran", "restaurang", 124_000, paid_by="Sara", days_ago=14)
    malmo.expense("Taxi hem", "taxi", 28_900, paid_by="Du", days_ago=14)
    malmo.expense("Fika på Lilla Kafferosteriet", "fika", 24_400, paid_by="Ellen", days_ago=6)
    malmo.payment("Jonas", "Du", 15_000, days_ago=10)

    kbh = Group(api, you, "🇩🇰 Köpenhamnshelgen", "SEK", ["Jonas", "Sara"], friends)
    kbh.expense("Hotell Cabinn", "boende", 240_000, paid_by="Du", days_ago=8)
    kbh.expense("Smørrebrød på Schønnemann", "restaurang", 48_000, paid_by="Jonas", days_ago=7, currency="DKK")
    kbh.expense("Tivoli entré", "nöje", 62_000, paid_by="Sara", days_ago=7, currency="DKK")
    kbh.expense("Öresundståg", "resa", 35_700, paid_by="Du", days_ago=9)

    home = Group(api, you, "🏠 Lägenheten", "SEK", ["Alex"], friends)
    home.expense("Hyra augusti", "boende", 850_000, paid_by="Du", days_ago=3)
    home.expense("Städgrejer", "groceries", 30_400, paid_by="Alex", days_ago=12)
    home.expense("El-räkning", "övrigt", 94_200, paid_by="Alex", days_ago=5)

    print(f"Seeded for user {args.user}:")
    for group in (malmo, kbh, home):
        print(f"  {group.name} — {len(group.members)} members")
    print("Friends' Swish numbers:", ", ".join(f"{n} {s}" for n, s in FRIENDS.items()))
    print("Sign in on the app (Jag → Logga in) and pull — the groups arrive by discovery.")


class Api:
    def __init__(self, base: str) -> None:
        self.base = base

    def call(self, method: str, path: str, body=None, token: str | None = None):
        request = urllib.request.Request(self.base + path, method=method)
        request.add_header("Content-Type", "application/json")
        request.add_header("X-Kvitta-Build", "2")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        data = json.dumps(body).encode() if body is not None else None
        try:
            with urllib.request.urlopen(request, data) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raise SystemExit(f"{method} {path} -> {error.code}: {error.read().decode()[:300]}")

    def sign_in(self, user_id: str) -> dict:
        body = self.call("POST", "/api/v1/auth/dev", {"userId": user_id})
        return {"userId": body["userId"], "token": body["accessToken"]}

    def put_profile(self, session: dict, swish_number: str) -> None:
        self.call("PUT", "/api/v1/me/profile", {"swishNumber": swish_number}, session["token"])


class Group:
    """A group seeded through the real flow: you push the opening batch, friends join by invite."""

    def __init__(self, api: Api, you: dict, name: str, currency: str, friend_names, friends) -> None:
        self.api = api
        self.you = you
        self.name = name
        self.group_id = str(uuid.uuid4())
        self.members: dict[str, str] = {"Du": str(uuid.uuid4())}

        events = [
            self.envelope(self.group_id, "GroupCreated", {"name": name, "currency": currency}, you),
            self.envelope(self.members["Du"], "MemberAdded",
                          {"displayName": "Du", "linkedUserId": you["userId"]}, you),
        ]
        for friend in friend_names:
            self.members[friend] = str(uuid.uuid4())
            events.append(self.envelope(self.members[friend], "MemberAdded",
                                        {"displayName": friend, "linkedUserId": None}, you))
        self.push(events, you)

        # Friends claim their placeholders through the invite flow — the only way a user row
        # gets linked to a member, same as a real phone would.
        invite = api.call("POST", f"/api/v1/groups/{self.group_id}/invites", {}, you["token"])
        for friend in friend_names:
            api.call("POST", f"/api/v1/invites/{invite['token']}/accept",
                     {"memberId": self.members[friend]}, friends[friend]["token"])

    def expense(self, description, category, amount, paid_by, days_ago, currency="SEK") -> None:
        ids = list(self.members.values())
        share, remainder = divmod(amount, len(ids))
        shares = [{"memberId": m, "amountMinor": share + (1 if i < remainder else 0)}
                  for i, m in enumerate(sorted(ids))]
        payload = {
            "description": description, "categoryId": category,
            "date": self.date(days_ago), "currency": currency, "amountMinor": amount,
            "payers": [{"memberId": self.members[paid_by], "amountMinor": amount}],
            "shares": shares, "splitMethod": "equal",
        }
        self.push([self.envelope(str(uuid.uuid4()), "ExpenseCreated", payload,
                                 self.you, days_ago)], self.you)

    def payment(self, from_name, to_name, amount, days_ago, currency="SEK") -> None:
        payload = {
            "fromMemberId": self.members[from_name], "toMemberId": self.members[to_name],
            "currency": currency, "amountMinor": amount,
            "date": self.date(days_ago), "method": "swish",
        }
        self.push([self.envelope(str(uuid.uuid4()), "PaymentRecorded", payload,
                                 self.you, days_ago)], self.you)

    def envelope(self, entity, type_, payload, author, days_ago=30) -> dict:
        stamp = datetime.datetime.now(datetime.UTC) - datetime.timedelta(days=days_ago)
        return {
            "eventId": str(uuid.uuid4()), "groupId": self.group_id, "entityId": entity,
            "type": type_, "schemaVersion": 1, "authorId": author["userId"],
            "clientTimestamp": stamp.strftime("%Y-%m-%dT%H:%M:%SZ"), "payload": payload,
        }

    def push(self, events, author) -> None:
        outcome = self.api.call("POST", f"/api/v1/groups/{self.group_id}/events",
                                events, author["token"])
        rejected = outcome.get("rejected") or []
        if rejected:
            raise SystemExit(f"rejected in {self.name}: {rejected}")

    @staticmethod
    def date(days_ago: int) -> str:
        return (datetime.date.today() - datetime.timedelta(days=days_ago)).isoformat()


if __name__ == "__main__":
    main()
