// Mac Client — cc-anywhere
const { useState: useStateM, useEffect: useEffectM, useRef: useRefM } = React;

// ── Faux terminal content ────────────────────────────────────────
function TerminalLine({ children, style, dim, accent }) {
  return (
    <div style={{
      fontFamily: '"JetBrains Mono", "SF Mono", ui-monospace, Menlo, monospace',
      fontSize: 12.5, lineHeight: 1.62, whiteSpace: 'pre-wrap',
      color: dim ? 'var(--term-dim)' : accent || 'var(--term-fg)',
      ...style,
    }}>{children}</div>
  );
}

function TerminalView({ theme, typing = true }) {
  const t = theme;
  // CSS vars scoped to this terminal
  const vars = {
    '--term-bg': t.bg, '--term-fg': t.fg, '--term-dim': t.dim,
    '--term-cursor': t.cursor, '--term-sel': t.selection,
    '--term-a1': t.accent1, '--term-a2': t.accent2,
    '--term-a3': t.accent3, '--term-a4': t.accent4,
  };

  const streamed = useLoopType([
    '正在分析项目结构...',
    '检测到 14 个 .ts 文件中的潜在性能瓶颈',
    '建议：对 src/queue/scheduler.ts 第 84 行的 sort 替换为 priority queue',
  ], 28, 1500);

  return (
    <div style={{
      flex: 1, position: 'relative', overflow: 'hidden',
      background: t.bg, color: t.fg,
      borderRadius: 12, border: '1px solid var(--line)',
      ...vars,
    }}>
      {/* faint scanline texture */}
      <div style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        backgroundImage: 'linear-gradient(180deg, rgba(255,255,255,0.02) 50%, transparent 50%)',
        backgroundSize: '100% 3px', opacity: 0.5,
      }} />

      <div style={{ padding: '18px 22px', position: 'relative', zIndex: 1 }}>
        {/* Welcome banner */}
        <TerminalLine accent={t.accent2} style={{ fontWeight: 600, marginBottom: 6 }}>
          ╭─ Claude Code · session restored ─────────────────────────╮
        </TerminalLine>
        <TerminalLine dim>{`│  ~/project/refactor-engine · model: claude-sonnet-4.5  │`}</TerminalLine>
        <TerminalLine accent={t.accent2} style={{ fontWeight: 600, marginBottom: 14 }}>
          ╰──────────────────────────────────────────────────────────╯
        </TerminalLine>

        {/* User prompt */}
        <TerminalLine style={{ marginBottom: 2 }}>
          <span style={{ color: t.accent1 }}>{'❯ '}</span>
          <span>查一下 scheduler 里那段排序为什么慢, 给出优化方案</span>
        </TerminalLine>

        <div style={{ height: 10 }} />

        {/* Assistant thinking */}
        <TerminalLine dim style={{ marginBottom: 6 }}>
          <span style={{ color: t.accent4 }}>● </span>
          <span style={{ fontStyle: 'italic' }}>思考中 · 读取了 4 个文件 · 1.4s</span>
        </TerminalLine>

        {/* Tool use card */}
        <div style={{
          margin: '8px 0 12px', padding: '10px 12px',
          background: `${t.accent2}1A`,
          border: `1px solid ${t.accent2}55`,
          borderLeft: `3px solid ${t.accent2}`,
          borderRadius: 8,
        }}>
          <div style={{
            fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600,
            color: t.accent2, letterSpacing: 0.4, marginBottom: 4,
          }}>
            TOOL · Read
          </div>
          <TerminalLine style={{ color: t.fg, fontSize: 12 }}>
            src/queue/scheduler.ts <span style={{ color: t.dim }}>· 184 lines</span>
          </TerminalLine>
        </div>

        {/* Streaming assistant */}
        <TerminalLine style={{ marginBottom: 4 }}>
          <span style={{ color: t.accent4 }}>●</span> <span style={{ fontWeight: 600 }}>分析结果</span>
        </TerminalLine>
        <TerminalLine style={{ marginLeft: 14 }}>
          第 84 行使用了 <span style={{ color: t.accent1 }}>Array.prototype.sort</span> 在每次调度时
        </TerminalLine>
        <TerminalLine style={{ marginLeft: 14 }}>
          对 <span style={{ color: t.accent3 }}>O(n log n)</span> 的任务列表重排, 任务数超过 5k 时阻塞主线程
          <span style={{ color: t.accent3 }}>≈ 38ms</span>
        </TerminalLine>

        <div style={{ height: 10 }} />

        {/* Code block */}
        <div style={{
          background: `${t.fg}08`, border: `1px solid ${t.fg}15`,
          borderRadius: 8, padding: '10px 14px', marginLeft: 14,
        }}>
          <TerminalLine dim style={{ fontSize: 10.5, marginBottom: 6, letterSpacing: 0.4 }}>
            TYPESCRIPT · proposed
          </TerminalLine>
          <TerminalLine><span style={{ color: t.accent4 }}>import</span> {`{ MinHeap }`} <span style={{ color: t.accent4 }}>from</span> <span style={{ color: t.accent1 }}>"./heap"</span>;</TerminalLine>
          <TerminalLine><span style={{ color: t.accent4 }}>const</span> <span style={{ color: t.accent2 }}>queue</span> = <span style={{ color: t.accent4 }}>new</span> MinHeap{`<Task>`}(<span style={{ color: t.accent2 }}>byPriority</span>);</TerminalLine>
          <TerminalLine><span style={{ color: t.accent2 }}>queue</span>.push(task); <span style={{ color: t.dim }}>// O(log n) insert</span></TerminalLine>
        </div>

        <div style={{ height: 12 }} />

        {/* Tool use awaiting approval */}
        <div style={{
          padding: '12px 14px', borderRadius: 10,
          background: `${t.cursor}12`,
          border: `1px dashed ${t.cursor}80`,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8,
          }}>
            <div style={{
              width: 22, height: 22, borderRadius: 5,
              background: t.cursor, color: t.bg,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 11, fontWeight: 700,
            }}>✎</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 12, fontWeight: 600, color: t.fg }}>
                Edit · src/queue/scheduler.ts
              </div>
              <div style={{ fontSize: 11, color: t.dim }}>
                replace 12 lines · awaiting approval
              </div>
            </div>
            <div style={{ display: 'flex', gap: 6 }}>
              {['1 批准', '2 拒绝', '3 总是'].map((l,i) => (
                <div key={l} style={{
                  fontSize: 10.5, fontWeight: 600, padding: '4px 10px',
                  borderRadius: 6, fontFamily: 'inherit',
                  background: i === 0 ? t.cursor : `${t.fg}10`,
                  color: i === 0 ? t.bg : t.fg,
                }}>{l}</div>
              ))}
            </div>
          </div>
        </div>

        <div style={{ height: 14 }} />

        {/* Live streaming line */}
        <TerminalLine>
          <span style={{ color: t.accent1 }}>❯ </span>
          <span>{streamed}</span>
          <Cursor color={t.cursor} />
        </TerminalLine>
      </div>
    </div>
  );
}

// ── Top tab strip ────────────────────────────────────────────────
function MacTabStrip({ tabs, active, onPick }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-end', gap: 0,
      padding: '0 12px', height: 38, position: 'relative',
    }}>
      {tabs.map((tab, i) => {
        const isActive = i === active;
        return (
          <div key={tab.id} onClick={() => onPick && onPick(i)} style={{
            position: 'relative',
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '0 14px', height: 30, marginRight: 2,
            borderRadius: '8px 8px 0 0',
            background: isActive ? 'var(--bgElev)' : 'transparent',
            color: isActive ? 'var(--text)' : 'var(--textMuted)',
            border: isActive ? '1px solid var(--line)' : '1px solid transparent',
            borderBottom: isActive ? '1px solid var(--bgElev)' : '1px solid transparent',
            marginBottom: -1, fontSize: 12, fontWeight: 500,
            cursor: 'pointer', whiteSpace: 'nowrap', flexShrink: 0,
          }}>
            <PulseDot
              color={tab.status === 'running' ? 'var(--success)' : tab.status === 'error' ? 'var(--danger)' : 'var(--textFaint)'}
              size={7} pulse={tab.status === 'running' && isActive}
            />
            <span style={{ fontWeight: isActive ? 600 : 500 }}>{tab.name}</span>
            {tab.unread && (
              <span style={{
                fontSize: 9.5, fontWeight: 700, padding: '1px 5px', borderRadius: 8,
                background: 'var(--accent)', color: '#001019',
              }}>{tab.unread}</span>
            )}
            <Icon name="close" size={11} stroke="currentColor" />
          </div>
        );
      })}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        width: 28, height: 28, borderRadius: 6, marginLeft: 4,
        color: 'var(--textMuted)', cursor: 'pointer',
        marginBottom: 1,
      }}>
        <Icon name="plus" size={15} />
      </div>
    </div>
  );
}

// ── Sidebar (left) ──────────────────────────────────────────────
function MacSidebar() {
  return (
    <div style={{
      width: 196, flexShrink: 0, padding: '14px 10px 10px',
      display: 'flex', flexDirection: 'column', gap: 14,
      borderRight: '1px solid var(--line)',
      background: 'linear-gradient(180deg, var(--bgInset) 0%, transparent 100%)',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '0 4px' }}>
        <div style={{
          width: 26, height: 26, borderRadius: 7,
          background: 'linear-gradient(135deg, var(--accent), oklch(0.7 0.15 280))',
          display: 'grid', placeItems: 'center',
          boxShadow: '0 4px 12px -4px var(--accent)',
        }}>
          <div style={{ width: 10, height: 10, borderRadius: 2, background: '#fff', opacity: 0.95 }} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--text)', letterSpacing: -0.1 }}>cc-anywhere</div>
          <div style={{ fontSize: 10, color: 'var(--textFaint)', fontVariantNumeric: 'tabular-nums' }}>v0.4.2 · M3</div>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <SectionLabel style={{ padding: '0 6px', marginBottom: 4 }}>Workspaces</SectionLabel>
        {[
          { name: 'refactor-engine', path: '~/work/refactor', n: 3, active: true },
          { name: 'cc-anywhere', path: '~/work/cc', n: 0 },
          { name: 'site-2026', path: '~/work/site', n: 1 },
          { name: 'data-pipeline', path: '~/proj/data', n: 0, idle: true },
        ].map((w,i) => (
          <div key={w.name} style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '6px 8px', borderRadius: 7,
            background: w.active ? 'var(--accentSoft)' : 'transparent',
            color: w.active ? 'var(--accent)' : 'var(--text)',
            fontSize: 12, fontWeight: w.active ? 600 : 500,
            position: 'relative',
          }}>
            {w.active && <div style={{
              position: 'absolute', left: -10, top: '50%', transform: 'translateY(-50%)',
              width: 3, height: 16, borderRadius: 2, background: 'var(--accent)',
            }}/>}
            <PulseDot
              color={w.idle ? 'var(--textFaint)' : 'var(--success)'}
              size={6} pulse={!w.idle && w.active}
            />
            <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{w.name}</span>
            {w.n > 0 && <span style={{
              fontSize: 9.5, fontWeight: 700, color: w.active ? 'var(--accent)' : 'var(--textMuted)',
            }}>{w.n}</span>}
          </div>
        ))}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <SectionLabel style={{ padding: '0 6px', marginBottom: 4 }}>Mobile · 2 在线</SectionLabel>
        {[
          { name: 'Pixel 8 Pro', online: true, latency: '38ms' },
          { name: '小米 14 Ultra', online: true, latency: '52ms' },
        ].map(d => (
          <div key={d.name} style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '6px 8px', borderRadius: 7,
            fontSize: 11.5, color: 'var(--textMuted)',
          }}>
            <PulseDot color="var(--success)" size={6} pulse={false} />
            <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{d.name}</span>
            <span style={{ fontSize: 10, fontVariantNumeric: 'tabular-nums', color: 'var(--textFaint)' }}>{d.latency}</span>
          </div>
        ))}
      </div>

      <div style={{ flex: 1 }} />

      <div style={{
        padding: 10, borderRadius: 10,
        background: 'var(--bgInset)', border: '1px solid var(--line)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 6 }}>
          <Icon name="bolt" size={13} stroke="var(--accent)" />
          <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text)' }}>本次会话</span>
        </div>
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)',
          gap: 6, fontSize: 10.5, color: 'var(--textMuted)',
          fontVariantNumeric: 'tabular-nums',
        }}>
          <div>消息<span style={{ color: 'var(--text)', fontWeight: 600, marginLeft: 4 }}>247</span></div>
          <div>工具<span style={{ color: 'var(--text)', fontWeight: 600, marginLeft: 4 }}>34</span></div>
          <div>耗时<span style={{ color: 'var(--text)', fontWeight: 600, marginLeft: 4 }}>1h12m</span></div>
          <div>批准<span style={{ color: 'var(--text)', fontWeight: 600, marginLeft: 4 }}>5</span></div>
        </div>
      </div>
    </div>
  );
}

// ── Right activity panel ─────────────────────────────────────────
function MacActivityPanel() {
  const events = [
    { type: 'assistant', from: 'Claude', text: '建议替换为 priority queue', t: '14:08' },
    { type: 'tool', from: 'Read', text: 'scheduler.ts · 184L', t: '14:08' },
    { type: 'user', from: 'You', text: '查一下 scheduler 排序', t: '14:07', src: 'Mac' },
    { type: 'phone', from: 'Pixel 8 Pro', text: '批准 Edit · scheduler.ts', t: '14:05', src: 'phone' },
    { type: 'assistant', from: 'Claude', text: '已完成 search-and-replace × 3', t: '14:03' },
    { type: 'user', from: 'You', text: '把所有 sort 调用换成 heap', t: '14:01', src: 'phone' },
  ];
  const ev = (e) => {
    const colors = {
      assistant: 'var(--accent)', tool: 'var(--warn)',
      user: 'var(--success)', phone: 'oklch(0.72 0.18 320)',
    };
    return (
      <div key={e.t + e.text} style={{
        display: 'flex', gap: 10, padding: '8px 0',
        borderBottom: '1px dashed var(--line)',
      }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 2 }}>
            <div style={{ width: 5, height: 5, borderRadius: '50%', background: colors[e.type] }} />
            <span style={{ fontSize: 10.5, fontWeight: 700, color: 'var(--text)', letterSpacing: 0.2 }}>
              {e.from}
            </span>
            {e.src === 'phone' && (
              <span style={{
                fontSize: 9, padding: '1px 5px', borderRadius: 4,
                background: 'oklch(0.72 0.18 320 / 0.15)',
                color: 'oklch(0.78 0.18 320)', fontWeight: 600,
              }}>PHONE</span>
            )}
            <div style={{ flex: 1 }}/>
            <span style={{ fontSize: 9.5, color: 'var(--textFaint)', fontVariantNumeric: 'tabular-nums' }}>{e.t}</span>
          </div>
          <div style={{
            fontSize: 11, color: 'var(--textMuted)', lineHeight: 1.45,
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{e.text}</div>
        </div>
      </div>
    );
  };

  return (
    <div style={{
      width: 244, flexShrink: 0,
      padding: '14px 14px 10px', display: 'flex', flexDirection: 'column', gap: 12,
      borderLeft: '1px solid var(--line)',
      background: 'linear-gradient(180deg, transparent 0%, var(--bgInset) 100%)',
    }}>
      <div>
        <SectionLabel>实时事件流</SectionLabel>
        <div style={{
          fontSize: 11.5, color: 'var(--textMuted)', marginTop: 4,
          fontVariantNumeric: 'tabular-nums',
        }}>refactor-engine · session 7b3a</div>
      </div>

      <div style={{ display: 'flex', gap: 6 }}>
        {['全部', 'Tool', 'Phone'].map((l,i) => (
          <div key={l} style={{
            fontSize: 10.5, fontWeight: 600, padding: '3px 8px',
            borderRadius: 5, cursor: 'pointer',
            background: i === 0 ? 'var(--accent)' : 'var(--bgInset)',
            color: i === 0 ? '#001019' : 'var(--textMuted)',
          }}>{l}</div>
        ))}
        <div style={{ flex: 1 }} />
        <div style={{ color: 'var(--textFaint)' }}>
          <Icon name="pin" size={13} />
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
        {events.map(ev)}
      </div>

      <div style={{
        padding: 10, borderRadius: 10, background: 'var(--bgElev)',
        border: '1px solid var(--line)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
          <PulseDot color="var(--success)" size={6} />
          <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text)' }}>Server 健康</span>
          <div style={{ flex: 1 }} />
          <span style={{ fontSize: 10, color: 'var(--textFaint)', fontVariantNumeric: 'tabular-nums' }}>38ms</span>
        </div>
        {/* Sparkline */}
        <svg width="100%" height="28" viewBox="0 0 200 28" preserveAspectRatio="none">
          <defs>
            <linearGradient id="spk" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--accent)" stopOpacity="0.5"/>
              <stop offset="100%" stopColor="var(--accent)" stopOpacity="0"/>
            </linearGradient>
          </defs>
          <path d="M0,22 L20,14 L40,18 L60,8 L80,12 L100,4 L120,10 L140,7 L160,12 L180,5 L200,9 L200,28 L0,28 Z" fill="url(#spk)"/>
          <path d="M0,22 L20,14 L40,18 L60,8 L80,12 L100,4 L120,10 L140,7 L160,12 L180,5 L200,9" fill="none" stroke="var(--accent)" strokeWidth="1.5"/>
        </svg>
      </div>
    </div>
  );
}

// ── Window chrome ────────────────────────────────────────────────
function MacChrome({ children, dark }) {
  return (
    <div style={{
      width: 1240, height: 780, borderRadius: 16, overflow: 'hidden',
      background: 'var(--bg)',
      border: `1px solid ${dark ? 'rgba(255,255,255,0.10)' : 'rgba(15,23,42,0.12)'}`,
      boxShadow: dark
        ? '0 32px 80px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.04)'
        : '0 32px 80px rgba(15,23,42,0.25), 0 0 0 1px rgba(15,23,42,0.06)',
      display: 'flex', flexDirection: 'column', position: 'relative',
    }}>
      {/* Title bar with traffic lights */}
      <div style={{
        height: 36, flexShrink: 0,
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '0 14px', borderBottom: '1px solid var(--line)',
        background: 'var(--bgElev)', position: 'relative',
      }}>
        <div style={{ display: 'flex', gap: 8 }}>
          {['#ff5f57', '#febc2e', '#28c840'].map(c => (
            <div key={c} style={{
              width: 12, height: 12, borderRadius: '50%', background: c,
              border: '0.5px solid rgba(0,0,0,0.15)',
            }} />
          ))}
        </div>
        <div style={{ width: 1 }} />
        <div style={{
          flex: 1, display: 'flex', justifyContent: 'center',
          alignItems: 'center', gap: 14,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '4px 12px', borderRadius: 100,
            background: 'var(--bgInset)', border: '1px solid var(--line)',
            fontSize: 11.5, color: 'var(--textMuted)', fontWeight: 500,
          }}>
            <PulseDot color="var(--success)" size={6} />
            <span style={{ color: 'var(--text)', fontWeight: 600 }}>已连接</span>
            <span style={{ color: 'var(--textFaint)' }}>·</span>
            <span style={{ fontVariantNumeric: 'tabular-nums' }}>cc.example.com:8443</span>
            <span style={{ color: 'var(--textFaint)' }}>·</span>
            <Icon name="devices" size={11} stroke="var(--textMuted)" />
            <span style={{ fontVariantNumeric: 'tabular-nums', fontWeight: 600, color: 'var(--text)' }}>2</span>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8, color: 'var(--textMuted)' }}>
          <Icon name="history" size={15} />
          <Icon name="bell" size={15} />
          <Icon name="settings" size={15} />
        </div>
      </div>
      {children}
    </div>
  );
}

// ── Main Mac artboard ────────────────────────────────────────────
function MacMain({ theme, dark }) {
  const [tab, setTab] = useStateM(0);
  return (
    <MacChrome dark={dark}>
      <MacTabStrip
        active={tab} onPick={setTab}
        tabs={[
          { id: 'a', name: 'refactor-engine', status: 'running', unread: 0 },
          { id: 'b', name: 'cc-anywhere', status: 'running' },
          { id: 'c', name: 'site-2026', status: 'error', unread: 1 },
          { id: 'd', name: 'data-pipeline', status: 'idle' },
        ]}
      />
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        <MacSidebar />
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: 14, gap: 10, minWidth: 0 }}>
          {/* Path crumb */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 10, flexShrink: 0,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <Icon name="folder" size={13} stroke="var(--textMuted)" />
              <span style={{ fontSize: 12, color: 'var(--textMuted)', fontFamily: '"JetBrains Mono", ui-monospace' }}>
                ~/work/refactor-engine
              </span>
              <span style={{ color: 'var(--textFaint)' }}>/</span>
              <span style={{ fontSize: 12, color: 'var(--text)', fontWeight: 600 }}>
                src/queue/scheduler.ts
              </span>
            </div>
            <div style={{ flex: 1 }} />
            <StatusPill color="var(--success)" accent>
              <span style={{ fontWeight: 700, color: 'var(--text)' }}>session</span>
              <span style={{ color: 'var(--textFaint)' }}>·</span>
              <span style={{ fontFamily: 'ui-monospace' }}>7b3a-c4f1</span>
            </StatusPill>
            <StatusPill>
              <Icon name="palette" size={11} stroke="var(--textMuted)" />
              <span>{theme.name}</span>
            </StatusPill>
          </div>

          <TerminalView theme={theme} />

          {/* Command bar */}
          <div style={{
            flexShrink: 0, height: 44, display: 'flex', alignItems: 'center', gap: 8,
            padding: '0 12px', borderRadius: 12,
            background: 'var(--bgElev)', border: '1px solid var(--line)',
          }}>
            <Icon name="terminal" size={14} stroke="var(--accent)" />
            <span style={{
              fontFamily: '"JetBrains Mono", ui-monospace',
              fontSize: 12, color: 'var(--text)', fontWeight: 500,
            }}>
              <span style={{ color: 'var(--accent)' }}>❯</span> 继续重构 priority queue 并补上单测
              <Cursor color="var(--accent)" height="0.95em" />
            </span>
            <div style={{ flex: 1 }} />
            <div style={{ display: 'flex', gap: 6, alignItems: 'center', color: 'var(--textFaint)', fontSize: 11 }}>
              <span>⌘K</span><span>⌘↵</span>
            </div>
          </div>
        </div>
        <MacActivityPanel />
      </div>
    </MacChrome>
  );
}

// ── Preferences > Devices artboard ────────────────────────────────
function MacDevices({ theme, dark }) {
  return (
    <MacChrome dark={dark}>
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        {/* Inner nav */}
        <div style={{
          width: 192, padding: '20px 12px', borderRight: '1px solid var(--line)',
          background: 'var(--bgInset)',
        }}>
          <SectionLabel style={{ padding: '0 8px', marginBottom: 12 }}>偏好设置</SectionLabel>
          {[
            { i: 'cpu', l: '通用' },
            { i: 'wifi', l: 'Server 连接' },
            { i: 'devices', l: '设备管理', active: true },
            { i: 'palette', l: '终端主题' },
            { i: 'lock', l: '安全' },
            { i: 'file', l: '日志与诊断' },
          ].map(item => (
            <div key={item.l} style={{
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '7px 10px', borderRadius: 7,
              background: item.active ? 'var(--accentSoft)' : 'transparent',
              color: item.active ? 'var(--accent)' : 'var(--text)',
              fontSize: 12.5, fontWeight: item.active ? 600 : 500,
              marginBottom: 2,
            }}>
              <Icon name={item.i} size={13} stroke="currentColor" />
              <span>{item.l}</span>
            </div>
          ))}
        </div>

        {/* Body */}
        <div style={{ flex: 1, padding: '24px 28px', display: 'flex', gap: 24, overflow: 'auto' }}>
          {/* Left: device list */}
          <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 16 }}>
            <div>
              <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)', letterSpacing: -0.3 }}>
                设备管理
              </div>
              <div style={{ fontSize: 12.5, color: 'var(--textMuted)', marginTop: 4 }}>
                管理已绑定的手机端 · 每个 sub_token 可独立撤销
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[
                { name: 'Pixel 8 Pro', os: 'Android 14', bound: '2026-04-12', online: true, latency: '38ms' },
                { name: '小米 14 Ultra', os: 'Android 14 · HyperOS', bound: '2026-05-02', online: true, latency: '52ms' },
                { name: 'OnePlus 12', os: 'Android 14 · OxygenOS', bound: '2026-03-18', online: false, last: '5 分钟前' },
              ].map(d => (
                <GlassCard key={d.name} padding={14} style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                  <div style={{
                    width: 42, height: 60, borderRadius: 6,
                    background: 'linear-gradient(135deg, var(--accent), oklch(0.55 0.15 260))',
                    position: 'relative', flexShrink: 0,
                    boxShadow: '0 4px 12px -6px var(--accent)',
                  }}>
                    <div style={{
                      position: 'absolute', top: 4, left: '50%', transform: 'translateX(-50%)',
                      width: 14, height: 2, borderRadius: 1, background: 'rgba(255,255,255,0.4)',
                    }}/>
                    <div style={{
                      position: 'absolute', inset: '8px 4px 8px 4px', borderRadius: 3,
                      background: 'rgba(0,0,0,0.15)',
                    }}/>
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{ fontSize: 14, fontWeight: 600, color: 'var(--text)' }}>{d.name}</span>
                      {d.online ? (
                        <StatusPill color="var(--success)" accent>在线 · {d.latency}</StatusPill>
                      ) : (
                        <StatusPill color="var(--textFaint)">离线 · {d.last}</StatusPill>
                      )}
                    </div>
                    <div style={{ fontSize: 11.5, color: 'var(--textMuted)', marginTop: 4, fontFamily: '"JetBrains Mono", ui-monospace' }}>
                      {d.os} · 绑定于 {d.bound} · sub_token_{d.name.slice(0,3).toLowerCase()}…7a3f
                    </div>
                  </div>
                  <div style={{
                    fontSize: 11.5, fontWeight: 600, color: 'var(--danger)',
                    padding: '6px 12px', borderRadius: 7,
                    border: '1px solid color-mix(in oklab, var(--danger) 30%, transparent)',
                    background: 'color-mix(in oklab, var(--danger) 8%, transparent)',
                  }}>撤销</div>
                </GlassCard>
              ))}
            </div>
          </div>

          {/* Right: QR */}
          <div style={{ width: 290, flexShrink: 0 }}>
            <GlassCard padding={20} glow>
              <div style={{ textAlign: 'center', marginBottom: 12 }}>
                <SectionLabel>新设备绑定</SectionLabel>
                <div style={{ fontSize: 14, color: 'var(--text)', fontWeight: 600, marginTop: 4 }}>
                  扫一扫即可绑定
                </div>
              </div>
              {/* QR */}
              <div style={{
                width: 250, height: 250, borderRadius: 12,
                background: '#fff', padding: 16, margin: '0 auto',
                boxShadow: '0 12px 36px -16px var(--accent)',
                position: 'relative',
              }}>
                <FakeQR />
                <div style={{
                  position: 'absolute', inset: '50%', width: 40, height: 40,
                  margin: '-20px 0 0 -20px', borderRadius: 9,
                  background: 'linear-gradient(135deg, var(--accent), oklch(0.55 0.15 260))',
                  display: 'grid', placeItems: 'center',
                  boxShadow: '0 0 0 4px #fff',
                }}>
                  <div style={{ width: 14, height: 14, borderRadius: 3, background: '#fff' }}/>
                </div>
              </div>
              <div style={{
                marginTop: 14, textAlign: 'center',
                fontSize: 11.5, color: 'var(--textMuted)',
                fontVariantNumeric: 'tabular-nums',
              }}>
                有效期 <span style={{ color: 'var(--accent)', fontWeight: 700 }}>04:38</span>
              </div>
              <div style={{
                marginTop: 8, padding: '8px 10px', borderRadius: 7,
                background: 'var(--bgInset)', fontFamily: '"JetBrains Mono", ui-monospace',
                fontSize: 10.5, color: 'var(--textFaint)',
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>
                wss://cc.example.com:8443
              </div>
            </GlassCard>
          </div>
        </div>
      </div>
    </MacChrome>
  );
}

// ── Mac Terminal Themes picker ───────────────────────────────────
function MacThemes({ theme, dark, onPick }) {
  const themes = Object.entries(window.TERMINAL_THEMES);
  return (
    <MacChrome dark={dark}>
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        <div style={{
          width: 192, padding: '20px 12px', borderRight: '1px solid var(--line)',
          background: 'var(--bgInset)',
        }}>
          <SectionLabel style={{ padding: '0 8px', marginBottom: 12 }}>偏好设置</SectionLabel>
          {[
            { i: 'cpu', l: '通用' },
            { i: 'wifi', l: 'Server 连接' },
            { i: 'devices', l: '设备管理' },
            { i: 'palette', l: '终端主题', active: true },
            { i: 'lock', l: '安全' },
            { i: 'file', l: '日志与诊断' },
          ].map(item => (
            <div key={item.l} style={{
              display: 'flex', alignItems: 'center', gap: 10,
              padding: '7px 10px', borderRadius: 7,
              background: item.active ? 'var(--accentSoft)' : 'transparent',
              color: item.active ? 'var(--accent)' : 'var(--text)',
              fontSize: 12.5, fontWeight: item.active ? 600 : 500,
              marginBottom: 2,
            }}>
              <Icon name={item.i} size={13} stroke="currentColor" />
              <span>{item.l}</span>
            </div>
          ))}
        </div>

        <div style={{ flex: 1, padding: '24px 28px', display: 'flex', flexDirection: 'column', gap: 18, overflow: 'auto' }}>
          <div style={{ display: 'flex', alignItems: 'flex-end', gap: 18 }}>
            <div>
              <div style={{ fontSize: 22, fontWeight: 700, color: 'var(--text)', letterSpacing: -0.3 }}>
                终端主题
              </div>
              <div style={{ fontSize: 12.5, color: 'var(--textMuted)', marginTop: 4 }}>
                给 Claude Code 选一身合身的衣裳 · 切换实时生效
              </div>
            </div>
            <div style={{ flex: 1 }} />
            <StatusPill icon={<Icon name="sparkle" size={11} stroke="var(--accent)" />}>
              <span style={{ color: 'var(--text)', fontWeight: 600 }}>{theme.name}</span> 当前
            </StatusPill>
          </div>

          {/* Theme grid */}
          <div style={{
            display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14,
          }}>
            {themes.map(([key, t]) => (
              <div key={key} onClick={() => onPick && onPick(key)} style={{
                cursor: 'pointer',
                borderRadius: 14, overflow: 'hidden',
                border: t.name === theme.name
                  ? '2px solid var(--accent)'
                  : '1px solid var(--line)',
                background: 'var(--bgElev)',
                boxShadow: t.name === theme.name
                  ? '0 12px 32px -12px var(--accent)' : 'none',
                transition: 'transform 0.2s, box-shadow 0.2s',
                transform: t.name === theme.name ? 'translateY(-2px)' : 'none',
              }}>
                {/* preview */}
                <div style={{
                  height: 150, background: t.bg, position: 'relative',
                  fontFamily: '"JetBrains Mono", ui-monospace',
                  fontSize: 9.5, padding: '10px 12px', color: t.fg,
                }}>
                  <div style={{ display: 'flex', gap: 4, marginBottom: 8 }}>
                    {['#ff5f57','#febc2e','#28c840'].map(c => (
                      <div key={c} style={{ width: 6, height: 6, borderRadius: '50%', background: c, opacity: 0.6 }} />
                    ))}
                  </div>
                  <div style={{ color: t.accent2, fontWeight: 600 }}>● Claude</div>
                  <div style={{ marginTop: 2, color: t.dim }}>读取 scheduler.ts</div>
                  <div style={{ marginTop: 2 }}>
                    <span style={{ color: t.accent4 }}>const</span>{' '}
                    <span style={{ color: t.accent1 }}>queue</span> ={' '}
                    <span style={{ color: t.accent4 }}>new</span>{' '}
                    <span style={{ color: t.accent2 }}>MinHeap</span>();
                  </div>
                  <div style={{ marginTop: 2 }}>
                    <span style={{ color: t.accent3 }}>❯</span>{' '}
                    <span>继续</span>
                    <span style={{
                      display: 'inline-block', width: 4, height: 9, background: t.cursor,
                      marginLeft: 2, verticalAlign: 'middle',
                      animation: 'cc-blink 1s steps(2) infinite',
                    }}/>
                  </div>
                  {/* color swatches */}
                  <div style={{
                    position: 'absolute', bottom: 10, left: 12, right: 12,
                    display: 'flex', gap: 4,
                  }}>
                    {[t.accent1, t.accent2, t.accent3, t.accent4, t.cursor].map((c,i) => (
                      <div key={i} style={{
                        flex: 1, height: 6, borderRadius: 2, background: c,
                      }}/>
                    ))}
                  </div>
                </div>
                {/* meta */}
                <div style={{
                  padding: '10px 12px', display: 'flex', alignItems: 'center',
                }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>{t.name}</div>
                    <div style={{ fontSize: 10.5, color: 'var(--textFaint)' }}>{t.subtitle}</div>
                  </div>
                  {t.name === theme.name && (
                    <div style={{
                      width: 22, height: 22, borderRadius: '50%',
                      background: 'var(--accent)', color: 'var(--accentFg)',
                      display: 'grid', placeItems: 'center',
                    }}>
                      <Icon name="check" size={13} strokeWidth={2.4} />
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>

          {/* Custom controls */}
          <GlassCard padding={18} style={{ display: 'flex', alignItems: 'center', gap: 24 }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>跟随系统外观</div>
              <div style={{ fontSize: 11.5, color: 'var(--textMuted)', marginTop: 2 }}>
                白天浅色主题, 夜晚自动切换到深色
              </div>
            </div>
            <div style={{
              width: 42, height: 24, borderRadius: 12,
              background: 'var(--accent)', position: 'relative',
              boxShadow: 'inset 0 0 0 1px var(--lineStrong)',
            }}>
              <div style={{
                position: 'absolute', top: 2, right: 2, width: 20, height: 20,
                borderRadius: '50%', background: '#fff',
                boxShadow: '0 1px 4px rgba(0,0,0,0.25)',
              }}/>
            </div>

            <div style={{ width: 1, height: 30, background: 'var(--line)' }} />

            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>字号</div>
              <div style={{ fontSize: 11.5, color: 'var(--textMuted)', marginTop: 2 }}>
                JetBrains Mono · 13pt
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              {[11, 12, 13, 14, 16].map(s => (
                <div key={s} style={{
                  width: 26, height: 26, borderRadius: 6,
                  display: 'grid', placeItems: 'center',
                  background: s === 13 ? 'var(--accent)' : 'var(--bgInset)',
                  color: s === 13 ? 'var(--accentFg)' : 'var(--textMuted)',
                  fontSize: 11, fontWeight: 600,
                }}>{s}</div>
              ))}
            </div>
          </GlassCard>
        </div>
      </div>
    </MacChrome>
  );
}

// ── Fake QR pattern (deterministic noise) ────────────────────────
function FakeQR() {
  // Generate a 21x21 stable pattern
  const cells = [];
  const seed = (x, y) => ((x * 37 + y * 19 + (x ^ y) * 7) % 11) > 5;
  for (let y = 0; y < 25; y++) {
    for (let x = 0; x < 25; x++) {
      const isCorner = (x < 7 && y < 7) || (x > 17 && y < 7) || (x < 7 && y > 17);
      cells.push({ x, y, on: isCorner || seed(x, y) });
    }
  }
  return (
    <svg viewBox="0 0 25 25" style={{ width: '100%', height: '100%' }}>
      {cells.filter(c => c.on).map((c,i) => (
        <rect key={i} x={c.x} y={c.y} width="1" height="1" fill="#0c111c" rx="0.15"/>
      ))}
      {/* finder patterns */}
      {[[0,0],[18,0],[0,18]].map(([fx,fy], i) => (
        <g key={i} fill="none" stroke="#0c111c">
          <rect x={fx+0.5} y={fy+0.5} width="6" height="6" strokeWidth="1" fill="#fff"/>
          <rect x={fx+1.5} y={fy+1.5} width="4" height="4" strokeWidth="1"/>
          <rect x={fx+2} y={fy+2} width="3" height="3" fill="#0c111c"/>
        </g>
      ))}
    </svg>
  );
}

Object.assign(window, { MacMain, MacDevices, MacThemes });
