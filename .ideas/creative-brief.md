# Creative Brief: mobileworm

## Summary

mobileworm is a lightweight iOS companion for EarWorm that connects to an existing EarWorm desktop server and presents EarWorm's already-built mobile web interface inside a native iPhone shell.

The goal is not to rebuild EarWorm natively. The app should provide a clean iOS entry flow, remember the user's server after first launch, validate that the target is a real EarWorm server over HTTPS, and then hand the user into the existing EarWorm mobile login and browsing experience.

## Problem

EarWorm already has a mobile-facing browser UI, but reaching it from an iPhone currently depends on opening a browser manually, entering the server URL, and treating the experience like a website rather than an app.

This creates friction for personal use and TestFlight testing:

- the user has to remember or re-enter the server URL
- there is no native first-run setup flow
- there is no app-level place to change the server later
- there is no iOS-native validation that the entered URL is actually an EarWorm server

## Audience

- Primary user: the EarWorm operator and close testers using iPhone via personal TestFlight distribution
- Environment: trusted personal devices connecting to an EarWorm desktop instance over LAN HTTPS or an HTTPS tunnel URL
- Technical tolerance: high enough to understand server URLs, but the app should remove repetitive setup steps

## Product Goal

Create the thinnest viable iOS shell around EarWorm's existing mobile web app so that iPhone access feels like a real app without duplicating the web/mobile interface already maintained in the desktop project.

## Success Criteria

- On first launch, the app asks for an EarWorm server URL and validates it before proceeding.
- After a successful connection, the app remembers the server and goes directly back into EarWorm on later launches.
- The login experience is EarWorm's existing login page, not a separate native login implementation.
- The login screen includes a clear native affordance to change the saved server.
- The app rejects non-HTTPS URLs and surfaces a clear error when the target does not appear to be EarWorm.
- The v1 app is small in scope, shippable through personal TestFlight, and avoids rebuilding the mobile UI in SwiftUI.

## Product Principles

- Reuse, do not rewrite: prefer embedding EarWorm's mobile web experience over rebuilding screens natively.
- Native where it matters: use native UI for first-run connection, saved-server management, loading, and failure recovery.
- Keep trust explicit: only connect to HTTPS servers and verify the server looks like EarWorm before loading the web app.
- Stay small for v1: optimize for reliability and low maintenance over feature breadth.

## V1 Scope Statement

mobileworm v1 is a single-server iPhone app with a native server-entry flow and an embedded EarWorm web session. It is intentionally not a full native client, multi-server manager, or offline-first product.

## Inspiration and Research Notes

- EarWorm already supports browser-mode auth and mobile routes through its LAN server and mobile React views.
- Jellyfin's Swiftfin validates the manually entered server URL against a public server-info endpoint before sign-in, stores the resolved server, and then proceeds into sign-in. That is the right pattern to borrow for EarWorm.
- Jellyfin's iOS app family also validates the viability of a web-wrapper approach for self-hosted media clients, especially when the server already owns the main authenticated UI.
