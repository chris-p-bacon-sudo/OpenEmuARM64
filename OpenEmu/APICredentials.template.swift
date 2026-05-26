// APICredentials.template.swift
// ─────────────────────────────────────────────────────────────────────────────
// SETUP INSTRUCTIONS
// ─────────────────────────────────────────────────────────────────────────────
// 1. Copy this file and rename it:
//      APICredentials.template.swift  →  APICredentials.swift
//
// 2. Fill in your developer credentials:
//
//    SteamGridDB — register at https://www.steamgriddb.com/api/v2
//      Dashboard → your app → API Key
//
//    IGDB/Twitch — register at https://dev.twitch.tv
//      Dashboard → your app → Client ID + Client Secret
//
// 3. APICredentials.swift is gitignored — never commit it.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

extension SteamGridDBClient {
    static let apiKey = "YOUR_STEAMGRIDDB_API_KEY"
}

extension IGDBClient {
    static let clientID     = "YOUR_IGDB_CLIENT_ID"
    static let clientSecret = "YOUR_IGDB_CLIENT_SECRET"
}
