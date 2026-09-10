const SOUND_ASK = "C:\\Windows\\Media\\Windows Ding.wav"
const SOUND_DONE = "C:\\Windows\\Media\\tada.wav"

import { spawn } from "node:child_process"

const MIN_GAP = 500
let last = { ask: 0, done: 0 }

function play(file) {
  try {
    const child = spawn(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", `(New-Object Media.SoundPlayer '${file}').PlaySync()`],
      { stdio: "ignore", detached: true, windowsHide: true },
    )
    child.unref()
  } catch {}
}

const NUDGE_MAX = 3
const NUDGE_TEXT =
  "Your previous response hit the output token limit before finishing. Continue exactly where you stopped: complete the pending task or tool calls. Do not summarize, do not apologize, do not repeat already-delivered content."

const nudges = new Map()
const resuming = new Set()

async function isMain(client, sessionID) {
  try {
    const res = await client.session.get({ path: { id: sessionID } })
    if (res.data?.parentID) return false
  } catch {}
  return true
}

async function lastAssistant(client, sessionID) {
  const res = await client.session.messages({ path: { id: sessionID } })
  const msgs = res.data ?? []
  for (let i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i]?.info?.role === "assistant") return msgs[i].info
  }
  return null
}

async function nudge(client, sessionID) {
  const count = nudges.get(sessionID) ?? 0
  if (count >= NUDGE_MAX || resuming.has(sessionID)) return false
  resuming.add(sessionID)
  try {
    await client.session.promptAsync({
      path: { id: sessionID },
      body: { parts: [{ type: "text", text: NUDGE_TEXT }] },
    })
    nudges.set(sessionID, count + 1)
    return true
  } catch {
    return false
  } finally {
    setTimeout(() => resuming.delete(sessionID), 1500)
  }
}

export const SoundPlugin = async ({ client }) => {
  return {
    event: async ({ event }) => {
      try {
        if (event.type === "permission.asked" || event.type === "question.asked") {
          const now = Date.now()
          if (now - last.ask < MIN_GAP) return
          last.ask = now
          play(SOUND_ASK)
          return
        }
        if (event.type === "session.idle") {
          const sessionID = event.properties?.sessionID
          if (!sessionID) return
          const main = await isMain(client, sessionID)
          if (main) {
            const info = await lastAssistant(client, sessionID)
            if (info?.finish === "length" && !info.error) {
              const ok = await nudge(client, sessionID)
              if (ok) return
            }
          }
          const now = Date.now()
          if (now - last.done < MIN_GAP) return
          last.done = now
          play(SOUND_DONE)
        }
      } catch {}
    },
  }
}