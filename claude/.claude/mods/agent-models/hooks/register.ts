import type { Register } from 'claude-code'

type Fs = { fs: { write: (path: string, text: string) => Promise<void> } }

let seen: { models: Record<string, string>; efforts: Record<string, string>; usage: Record<string, number[]> } = { models: {}, efforts: {}, usage: {} }
let sessionId = ''
let viewedId: string | undefined
let lastView: string | undefined

const short = (model: string) => model.replace(/^claude-/, '').replace(/-\d.*$/, '')
const pretty = (model: string) => {
  const [name = '', ...version] = model.replace(/^claude-/, '').replace(/-\d{8}$/, '').split('-')
  return `${name.charAt(0).toUpperCase()}${name.slice(1)} ${version.join('.')}`.trim()
}
const seenFile = () => `/tmp/claude-agent-seen-${sessionId}.json`
const saveSeen = ($: Fs) => (sessionId ? $.fs.write(seenFile(), JSON.stringify(seen)) : undefined)

const writeView = async ($: Fs) => {
  const model = viewedId && seen.models[viewedId]
  const view = model ? [pretty(model), seen.efforts[viewedId!] ?? '', ...(seen.usage[viewedId!] ?? [])].join('|') : ''
  if (sessionId && view !== lastView) await $.fs.write(`/tmp/claude-view-${sessionId}`, (lastView = view))
}

export const register: Register = on => {
  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.agentId) {
      seen.models[started.agentId] = started.model
      await saveSeen($)
    }
    return started
  })

  on('classic.PostToolUse', async ($, e, next) => {
    if (e.agent_id && e.effort && seen.efforts[e.agent_id] !== e.effort.level) {
      seen.efforts[e.agent_id] = e.effort.level
      await saveSeen($)
    }
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    const start = Math.floor(Date.now() / 1000)
    const step = yield* next(e)
    const u = step.usage
    if (u && !e.agentId && sessionId) await $.fs.write(`/tmp/claude-cache-${sessionId}`, String(start))
    if (e.agentId && u) {
      seen.usage[e.agentId] = [u.input_tokens, u.cache_creation_input_tokens, u.cache_read_input_tokens, u.output_tokens, start]
      await saveSeen($)
      await writeView($)
    }
    return step
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    viewedId = e.props.view.agentId
    await writeView($)
    return next(e)
  })

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    sessionId = await $.session.id()
    seen = { ...seen, ...(await $.fs.read(seenFile()).then(JSON.parse, () => ({}))) }
    let lastAgents: string | undefined
    $.clock.every(1000, async () => {
      const counts: Record<string, number> = {}
      for (const a of await $.agent.list()) {
        const model = seen.models[a.id]
        if (a.status === 'running' && model) counts[short(model)] = (counts[short(model)] ?? 0) + 1
      }
      const agents = Object.entries(counts).sort().map(([m, n]) => `${m} x${n}`).join(' ')
      if (agents !== lastAgents) await $.fs.write(`/tmp/claude-agents-${sessionId}`, (lastAgents = agents))
      await writeView($)
    })
    return started
  })
}
