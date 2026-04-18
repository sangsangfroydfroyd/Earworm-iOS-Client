# App Freedom Compatibility Snapshot: mobileworm

Generated: 2026-04-18T07:13:44.960Z
Configured backend: mempalace
Active backend: app_freedom

This file remains as a deterministic App Freedom resume snapshot while MemPalace is the primary long-term memory backend.

## Current Objective

Not recorded.

## Workflow

Not recorded.

## Latest Change

Tightened fullscreen fit after bottom safe-area remained visible. Web destination now ignores safe areas at the RootView route level, RootView hides navigation toolbar and paints a safe fallback background, and WebContainerView uses overlay instead of safeAreaInset for unauthenticated Change Server so the WKWebView is no longer resized by native bottom insets. Simulator build/run and screenshot sanity check passed; security scan had no findings.

Next step: Re-run on a healthy iOS simulator and compare login/home/library sizing against Safari on the same device profile.
