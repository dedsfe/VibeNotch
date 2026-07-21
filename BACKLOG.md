# Backlog — o que o Vibe Island tem e a gente não

Empilhado a partir dos prints/vídeos (site vibeisland.app + demo do Edward Luo).
Sem ordem de prioridade — é inventário.

1. ~~**Medidor de uso/rate-limit** no topo~~ ✅ feito — cápsula "claude 5h · 7d" no header (Keychain + endpoint oauth/usage, cache 60s); por provedor quando Codex/Gemini tiverem fonte de quota
2. ~~**Diff real no pedido de permissão**~~ ✅ feito — Edit mostra -velho/+novo, Write mostra preview; cap de 3 linhas por lado + "+N linhas"
3. **Botão Bypass** — terceira opção além de Allow/Deny
4. **Atalhos de teclado** — ⌘Y/⌘N pra allow/deny, ⌘1/2/3 pra escolhas
5. **AskUserQuestion na ilha** — opções numeradas com título + descrição (hoje ignoramos)
6. ~~**Atividade ao vivo**~~ ✅ feito — PostToolUse/UserPromptSubmit viram "activity" silencioso (linha + painel em tempo real, sem banner); melhoria futura: PreToolUse pra tools longas
7. ~~**Pill no notch fechado**~~ ✅ feito — 3 estados (🔵 trabalhando / 🟠 N esperando / 🟢 pronto + título por 5s), vão centrado no notch físico, animação suave; falta só ícone por agente
8. **Badge de modelo** (Fable 5, GPT-5.6) e **badge do terminal** (iTerm/Ghostty/Cursor) por sessão
9. **Tempo decorrido por sessão** (27m, 1h, <1m)
10. **"You: <último prompt>"** no header + formato "projeto · título da task"
11. **Fecho formatado** — resumo multi-linha com bullets do que foi feito (não só 1 frase)
12. **Arquivar sessão** (lixeira) e **pop-out** da ilha (⌥⇥↗)
13. **Sound alerts 8-bit** por evento + toggle de som e engrenagem de settings na ilha
14. **Plan Review** — plano em Markdown renderizado na ilha + campo de feedback (ExitPlanMode)
15. **Zero Config** — auto-configura hooks de todos os CLIs num clique
16. **26 agentes** (Cursor, Copilot, Droid, Amp, Kiro…) e **20+ terminais** com split pane preciso
17. **SSH Remote** — monitorar agentes em servidor remoto
18. **Mascote/ícone pixel-art por agente** (identidade visual por CLI)

## Já empatamos de graça
- Pure Swift nativo (boringNotch) · Fully Local (protocolo 100% localhost)
- Allow/Deny da ilha destravando o CLI · "Sempre" gravando regra estreita no settings
- Pulo pro terminal por tty (Terminal.app + iTerm) · título da conversa (ai-title) · frase de fecho
