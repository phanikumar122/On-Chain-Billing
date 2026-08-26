Overview and feature list (automated billing, multi-token, subscriptions, invoicing, payment verification/receipts, dispute resolution, access control, gas optimization).
Prerequisites: Aptos CLI install, aptos init for a devnet profile.
Build: aptos move compile --named-addresses billing=<addr>
Test: aptos move test
Publish: aptos move publish --named-addresses billing=<addr> --profile devnet
Module + entry-function reference with example CLI aptos move run calls for create_invoice, pay_invoice, authorize, charge, and admin ops.
Architecture notes explaining the pull + pre-authorization subscription model and why it needs no trusted scheduler.
