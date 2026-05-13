// Mobile client (Android) for cc-anywhere
const { useState: useStateMo, useEffect: useEffectMo } = React;

// ── Phone frame (custom, taller bezel) ───────────────────────────
function PhoneFrame({ children, dark, style }) {
  return (
    <div style={{
      width: 390, height: 800, borderRadius: 44,
      padding: 8, background: dark ? '#0a0c10' : '#1a1d24',
      boxShadow: dark
        ? '0 32px 80px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.06)'
        : '0 32px 80px rgba(15,23,42,0.35), 0 0 0 1px rgba(15,23,42,0.1)',
      position: 'relative',
      ...style,
    }}>
      <div style={{
        width: '100%', height: '100%', borderRadius: 36, overflow: 'hidden',
        background: 'var(--bg)', position: 'relative',
        display: 'flex', flexDirection: 'column',
      }}>
        {/* Status bar */}
        <div style={{
          height: 38, flexShrink: 0, position: 'relative',
          display: 'flex', alignItems: 'center', padding: '0 24px',
          fontFamily: 'system-ui',
          color: 'var(--text)', fontSize: 13.5, fontWeight: 600,
        }}>
          <span style={{ fontVariantNumeric: 'tabular-nums' }}>22:14</span>
          {/* Camera punch hole */}
          <div style={{
            position: 'absolute', left: '50%', top: 10, transform: 'translateX(-50%)',
            width: 24, height: 24, borderRadius: '50%', background: '#000',
          }}/>
          <div style={{ flex: 1 }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            <Icon name="wifi" size={14} stroke="currentColor" strokeWidth={2} />
            <div style={{
              width: 24, height: 11, borderRadius: 3,
              border: '1.4px solid currentColor', position: 'relative', padding: 1.5,
            }}>
              <div style={{
                position: 'absolute', right: -3, top: 3, width: 1.5, height: 5,
                background: 'currentColor', borderRadius: 1,
              }}/>
              <div style={{ width: '85%', height: '100%', background: 'currentColor', borderRadius: 1 }}/>
            </div>
          </div>
        </div>

        <div style={{ flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          {children}
        </div>

        {/* Bottom gesture bar */}
        <div style={{ height: 24, flexShrink: 0, display: 'grid', placeItems: 'center' }}>
          <div style={{
            width: 124, height: 4.5, borderRadius: 100,
            background: 'var(--text)', opacity: 0.85,
          }}/>
        </div>
      </div>
    </div>
  );
}

// ── 1. Welcome / Onboarding ───────────────────────────────────────
function MobileWelcome({ dark }) {
  return (
    <PhoneFrame dark={dark}>
      <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        <AuroraOrbs tone="cyan" />
        <div style={{
          position: 'relative', zIndex: 1,
          padding: '32px 28px 28px',
          display: 'flex', flexDirection: 'column', height: '100%',
        }}>
          {/* Big mark */}
          <div style={{
            width: 76, height: 76, borderRadius: 22,
            background: 'linear-gradient(135deg, var(--accent), oklch(0.55 0.18 280))',
            boxShadow: '0 20px 48px -16px var(--accent)',
            display: 'grid', placeItems: 'center',
            position: 'relative', overflow: 'hidden',
          }}>
            {/* inner pulse */}
            <div style={{
              position: 'absolute', inset: 8, borderRadius: 14,
              background: 'radial-gradient(circle at 30% 30%, rgba(255,255,255,0.45), transparent 60%)',
            }} />
            <div style={{
              fontFamily: '"JetBrains Mono", ui-monospace',
              fontSize: 28, fontWeight: 800, color: '#fff',
              position: 'relative', zIndex: 1, letterSpacing: -1,
            }}>
              cc
            </div>
            <div style={{
              position: 'absolute', bottom: 8, right: 10,
              width: 6, height: 6, borderRadius: '50%', background: '#fff',
              animation: 'cc-blink 1.2s steps(2) infinite',
            }}/>
          </div>

          <div style={{ marginTop: 36 }}>
            <SectionLabel>cc-anywhere · v0.4.2</SectionLabel>
            <div style={{
              fontSize: 36, fontWeight: 800, lineHeight: 1.05,
              color: 'var(--text)', marginTop: 12, letterSpacing: -0.8,
            }}>
              你的 Claude<br/>
              <span style={{
                background: 'linear-gradient(135deg, var(--accent), oklch(0.65 0.18 280))',
                WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
                backgroundClip: 'text',
              }}>随处可达</span>
            </div>
            <div style={{
              fontSize: 14.5, lineHeight: 1.5, color: 'var(--textMuted)',
              marginTop: 14, maxWidth: 280,
            }}>
              扫一扫绑定你的 Mac, 让命令行 AI 在通勤路上也能继续推进任务
            </div>
          </div>

          <div style={{ flex: 1 }} />

          {/* Feature chips */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 20 }}>
            {[
              { i: 'terminal', t: '集中管理多 Tab 会话', d: '一目了然' },
              { i: 'sparkle', t: '远程批准 tool_use', d: '< 500ms 双向' },
              { i: 'image', t: '随手发图给 Claude', d: '路上灵感即接即用' },
            ].map(f => (
              <div key={f.i} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '10px 14px', borderRadius: 12,
                background: 'var(--panel)',
                border: '1px solid var(--line)',
                backdropFilter: 'blur(20px)',
              }}>
                <div style={{
                  width: 32, height: 32, borderRadius: 8,
                  background: 'var(--accentSoft)',
                  display: 'grid', placeItems: 'center',
                  color: 'var(--accent)',
                }}>
                  <Icon name={f.i} size={15} />
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text)' }}>{f.t}</div>
                  <div style={{ fontSize: 11.5, color: 'var(--textMuted)' }}>{f.d}</div>
                </div>
              </div>
            ))}
          </div>

          <div style={{
            height: 52, borderRadius: 16,
            background: 'linear-gradient(135deg, var(--accent), oklch(0.6 0.18 250))',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            gap: 8, color: '#001019', fontWeight: 700, fontSize: 15.5,
            boxShadow: '0 12px 32px -10px var(--accent)',
            position: 'relative', overflow: 'hidden',
          }}>
            <Icon name="qr" size={17} strokeWidth={2.2} />
            <span>扫码绑定 Mac</span>
            {/* sheen */}
            <div style={{
              position: 'absolute', top: 0, left: '-50%', width: '50%', height: '100%',
              background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.3), transparent)',
              animation: 'cc-sheen 3.5s ease-in-out infinite',
            }}/>
          </div>
          <div style={{
            marginTop: 12, textAlign: 'center', fontSize: 12, color: 'var(--textMuted)',
          }}>
            没法扫码? <span style={{ color: 'var(--accent)', fontWeight: 600 }}>手动输入</span>
          </div>
        </div>
      </div>
    </PhoneFrame>
  );
}

// ── 2. Tab list ───────────────────────────────────────────────────
function MobileTabList({ dark }) {
  return (
    <PhoneFrame dark={dark}>
      {/* App bar */}
      <div style={{
        padding: '8px 20px 12px', flexShrink: 0,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '6px 12px 6px 6px', borderRadius: 100,
          background: 'var(--bgInset)', border: '1px solid var(--line)',
          width: 'fit-content',
        }}>
          <div style={{
            width: 26, height: 26, borderRadius: '50%',
            background: 'var(--success)', position: 'relative',
            display: 'grid', placeItems: 'center',
          }}>
            <Icon name="cpu" size={12} stroke="#001019" strokeWidth={2.2} />
            <div style={{
              position: 'absolute', inset: -3, borderRadius: '50%',
              background: 'var(--success)', opacity: 0.3,
              animation: 'cc-pulse 1.8s ease-out infinite',
            }}/>
          </div>
          <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text)' }}>Mac 在线</span>
          <span style={{ fontSize: 11.5, color: 'var(--textFaint)', fontVariantNumeric: 'tabular-nums' }}>
            · 38ms
          </span>
        </div>

        <div style={{
          display: 'flex', alignItems: 'flex-end', gap: 10, marginTop: 18,
        }}>
          <div style={{
            fontSize: 30, fontWeight: 800, color: 'var(--text)', letterSpacing: -0.7,
            lineHeight: 1,
          }}>会话</div>
          <div style={{
            fontSize: 16, fontWeight: 700, color: 'var(--textFaint)',
            fontVariantNumeric: 'tabular-nums', paddingBottom: 2,
          }}>4</div>
          <div style={{ flex: 1 }} />
          <div style={{ display: 'flex', gap: 6, color: 'var(--textMuted)' }}>
            <div style={{
              width: 34, height: 34, borderRadius: '50%',
              background: 'var(--bgInset)', display: 'grid', placeItems: 'center',
            }}><Icon name="refresh" size={14}/></div>
            <div style={{
              width: 34, height: 34, borderRadius: '50%',
              background: 'var(--bgInset)', display: 'grid', placeItems: 'center',
            }}><Icon name="settings" size={14}/></div>
          </div>
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '4px 16px 16px' }}>
        {[
          { name: 'refactor-engine', path: '~/work/refactor', status: 'running', t: '3 分钟前',
            unread: 2, preview: '建议替换为 priority queue · O(log n) 插入', tool: true },
          { name: 'cc-anywhere', path: '~/work/cc', status: 'running', t: '14 分钟前',
            preview: '完成了 Android 端的扫码流程, 等下一步指令', tool: false },
          { name: 'site-2026', path: '~/work/site', status: 'error', t: '1 小时前',
            preview: 'Claude Code 进程异常退出 · 退出码 1', error: true },
          { name: 'data-pipeline', path: '~/proj/data', status: 'idle', t: '昨天',
            preview: '已生成 14 份周报草稿, 等待审阅' },
        ].map((tab, i) => (
          <div key={tab.name} style={{
            marginBottom: 10, padding: 14, borderRadius: 16,
            background: 'var(--bgElev)',
            border: '1px solid var(--line)',
            position: 'relative',
            boxShadow: i === 0 ? '0 6px 20px -10px var(--accent)' : 'none',
          }}>
            {/* leading rail */}
            {tab.status === 'running' && (
              <div style={{
                position: 'absolute', left: 0, top: 14, bottom: 14, width: 3,
                borderRadius: 2, background: 'var(--accent)',
              }}/>
            )}
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
              <PulseDot
                color={tab.status === 'running' ? 'var(--success)' : tab.status === 'error' ? 'var(--danger)' : 'var(--textFaint)'}
                size={8} pulse={tab.status === 'running' && i === 0}
              />
              <span style={{ fontSize: 15, fontWeight: 700, color: 'var(--text)', letterSpacing: -0.1 }}>
                {tab.name}
              </span>
              <div style={{ flex: 1 }} />
              {tab.tool && (
                <div style={{
                  display: 'flex', alignItems: 'center', gap: 4,
                  fontSize: 10.5, fontWeight: 700, padding: '3px 7px',
                  borderRadius: 100, background: 'oklch(0.78 0.16 70 / 0.18)',
                  color: 'oklch(0.78 0.16 70)',
                }}>
                  <div style={{ width: 5, height: 5, borderRadius: '50%', background: 'oklch(0.78 0.16 70)' }}/>
                  待批准
                </div>
              )}
              {tab.unread && (
                <div style={{
                  minWidth: 20, height: 20, borderRadius: 100,
                  background: 'var(--accent)', color: 'var(--accentFg)',
                  display: 'grid', placeItems: 'center',
                  fontSize: 10.5, fontWeight: 700, padding: '0 6px',
                }}>{tab.unread}</div>
              )}
            </div>
            <div style={{
              fontSize: 12.5, lineHeight: 1.45, marginBottom: 8,
              fontFamily: tab.error ? '"JetBrains Mono", ui-monospace' : 'inherit',
              color: tab.error ? 'var(--danger)' : 'var(--textMuted)',
              display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
            }}>{tab.preview}</div>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 8,
              fontSize: 11, color: 'var(--textFaint)',
            }}>
              <Icon name="folder" size={11} />
              <span style={{ fontFamily: '"JetBrains Mono", ui-monospace' }}>{tab.path}</span>
              <span>·</span>
              <span>{tab.t}</span>
            </div>
          </div>
        ))}
      </div>
    </PhoneFrame>
  );
}

// ── 3. Chat / Message stream with tool_use ──────────────────────
function MobileChat({ dark }) {
  return (
    <PhoneFrame dark={dark}>
      {/* Header */}
      <div style={{
        padding: '4px 16px 10px', flexShrink: 0,
        display: 'flex', alignItems: 'center', gap: 10,
        borderBottom: '1px solid var(--line)',
      }}>
        <div style={{
          width: 34, height: 34, borderRadius: '50%',
          background: 'var(--bgInset)', display: 'grid', placeItems: 'center',
          color: 'var(--textMuted)',
        }}><Icon name="arrowLeft" size={16}/></div>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: 15, fontWeight: 700, color: 'var(--text)' }}>refactor-engine</span>
            <PulseDot color="var(--success)" size={6} />
          </div>
          <div style={{ fontSize: 11, color: 'var(--textFaint)', fontFamily: '"JetBrains Mono", ui-monospace' }}>
            ~/work/refactor · 247 msg
          </div>
        </div>
        <div style={{ color: 'var(--textMuted)' }}><Icon name="settings" size={17}/></div>
      </div>

      {/* Messages */}
      <div style={{ flex: 1, overflow: 'auto', padding: '12px 14px' }}>
        {/* time sep */}
        <div style={{
          textAlign: 'center', fontSize: 10.5, color: 'var(--textFaint)',
          margin: '8px 0 16px', letterSpacing: 0.6,
        }}>今天 14:01</div>

        {/* User msg */}
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 14 }}>
          <div style={{
            maxWidth: '78%', padding: '10px 14px',
            background: 'linear-gradient(135deg, var(--accent), oklch(0.6 0.16 240))',
            color: 'var(--accentFg)',
            borderRadius: '18px 18px 4px 18px',
            fontSize: 14, lineHeight: 1.45, fontWeight: 500,
            boxShadow: '0 4px 14px -6px var(--accent)',
          }}>
            把所有 sort 调用换成 heap
          </div>
        </div>

        {/* Assistant text */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          <div style={{
            width: 26, height: 26, borderRadius: 7, flexShrink: 0,
            background: 'linear-gradient(135deg, oklch(0.7 0.18 280), var(--accent))',
            display: 'grid', placeItems: 'center', marginTop: 2,
            boxShadow: '0 4px 10px -4px oklch(0.7 0.18 280)',
          }}>
            <Icon name="sparkle" size={13} stroke="#fff" strokeWidth={2} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--textMuted)', marginBottom: 4 }}>
              Claude · 14:01
            </div>
            <div style={{
              padding: '12px 14px', borderRadius: '4px 18px 18px 18px',
              background: 'var(--bgElev)', border: '1px solid var(--line)',
              fontSize: 14, lineHeight: 1.55, color: 'var(--text)',
            }}>
              已读取 <code style={{
                fontFamily: '"JetBrains Mono", ui-monospace',
                fontSize: 12, padding: '1px 6px', borderRadius: 4,
                background: 'var(--accentSoft)', color: 'var(--accent)',
              }}>scheduler.ts</code>。共发现 <b>3</b> 处需要替换的 sort 调用,
              建议引入 <b>MinHeap</b> 实现 O(log n) 插入。准备就绪后我会逐一改写。
            </div>
          </div>
        </div>

        {/* Tool use card — pending approval */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          <div style={{
            width: 26, height: 26, borderRadius: 7, flexShrink: 0,
            background: 'var(--warn)', display: 'grid', placeItems: 'center',
            marginTop: 2,
          }}>
            <Icon name="edit" size={13} stroke="#3a2700" strokeWidth={2} />
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--textMuted)', marginBottom: 4, display: 'flex', alignItems: 'center', gap: 6 }}>
              <span>Edit · 待批准</span>
              <div style={{
                fontSize: 9.5, padding: '1px 5px', borderRadius: 4,
                background: 'oklch(0.78 0.16 70 / 0.2)',
                color: 'oklch(0.78 0.16 70)', fontWeight: 700,
              }}>TOOL_USE</div>
            </div>
            <div style={{
              padding: 14, borderRadius: '4px 18px 18px 18px',
              background: 'var(--bgElev)', border: '1px solid var(--warn)',
              boxShadow: '0 6px 20px -10px var(--warn)',
            }}>
              <div style={{
                display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
                fontFamily: '"JetBrains Mono", ui-monospace',
                fontSize: 12, color: 'var(--text)',
              }}>
                <Icon name="file" size={13} stroke="var(--accent)" />
                <span style={{ fontWeight: 600 }}>scheduler.ts</span>
                <span style={{ color: 'var(--textFaint)' }}>:84</span>
              </div>
              {/* diff */}
              <div style={{
                background: 'var(--bgInset)', borderRadius: 8, padding: '8px 10px',
                fontFamily: '"JetBrains Mono", ui-monospace', fontSize: 11.5,
                lineHeight: 1.55, marginBottom: 12,
              }}>
                <div style={{ color: 'var(--danger)' }}>− tasks.sort(byPriority)</div>
                <div style={{ color: 'var(--danger)' }}>− const next = tasks.shift()</div>
                <div style={{ color: 'var(--success)' }}>+ queue.push(task)</div>
                <div style={{ color: 'var(--success)' }}>+ const next = queue.pop()</div>
              </div>
              {/* approval buttons */}
              <div style={{ display: 'flex', gap: 8 }}>
                <div style={{
                  flex: 1, height: 38, borderRadius: 10,
                  background: 'var(--success)', color: '#001a0d',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  gap: 6, fontSize: 13, fontWeight: 700,
                  boxShadow: '0 6px 16px -8px var(--success)',
                }}>
                  <Icon name="check" size={15} strokeWidth={2.6} />
                  批准
                </div>
                <div style={{
                  flex: 1, height: 38, borderRadius: 10,
                  background: 'var(--bgInset)', color: 'var(--text)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  gap: 6, fontSize: 13, fontWeight: 600,
                  border: '1px solid var(--line)',
                }}>
                  <Icon name="x" size={14} strokeWidth={2.2} />
                  拒绝
                </div>
                <div style={{
                  height: 38, padding: '0 12px', borderRadius: 10,
                  background: 'var(--bgInset)', color: 'var(--textMuted)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  gap: 6, fontSize: 12, fontWeight: 600,
                  border: '1px solid var(--line)',
                }}>
                  总是
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Thinking collapsed */}
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          <div style={{ width: 26, flexShrink: 0 }}/>
          <div style={{
            flex: 1, padding: '8px 12px', borderRadius: 12,
            background: 'var(--bgInset)', border: '1px dashed var(--line)',
            display: 'flex', alignItems: 'center', gap: 8,
            fontSize: 12, color: 'var(--textMuted)',
          }}>
            <Icon name="sparkle" size={12} stroke="var(--textFaint)" />
            <span style={{ fontStyle: 'italic' }}>思考中 · 4.2s</span>
            <div style={{ flex: 1 }}/>
            <Icon name="chevronDown" size={12} />
          </div>
        </div>

        {/* Live typing */}
        <div style={{ display: 'flex', gap: 8 }}>
          <div style={{
            width: 26, height: 26, borderRadius: 7, flexShrink: 0,
            background: 'linear-gradient(135deg, oklch(0.7 0.18 280), var(--accent))',
            display: 'grid', placeItems: 'center', marginTop: 2,
          }}>
            <Icon name="sparkle" size={13} stroke="#fff" strokeWidth={2} />
          </div>
          <div style={{
            padding: '10px 14px', borderRadius: '4px 18px 18px 4px',
            background: 'var(--bgElev)', border: '1px solid var(--line)',
            display: 'flex', alignItems: 'center', gap: 6,
          }}>
            {[0,1,2].map(i => (
              <div key={i} style={{
                width: 6, height: 6, borderRadius: '50%', background: 'var(--accent)',
                animation: `cc-bounce 1.2s ease-in-out infinite ${i * 0.15}s`,
              }}/>
            ))}
          </div>
        </div>
      </div>

      {/* Input bar */}
      <div style={{
        flexShrink: 0, padding: '10px 14px 12px',
        borderTop: '1px solid var(--line)', background: 'var(--bg)',
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '6px 8px 6px 14px', borderRadius: 24,
          background: 'var(--bgInset)', border: '1px solid var(--line)',
        }}>
          <Icon name="image" size={18} stroke="var(--textMuted)" />
          <span style={{ flex: 1, fontSize: 13.5, color: 'var(--textFaint)' }}>
            发消息给 refactor-engine…
          </span>
          <div style={{
            width: 34, height: 34, borderRadius: '50%',
            background: 'linear-gradient(135deg, var(--accent), oklch(0.6 0.16 240))',
            display: 'grid', placeItems: 'center',
            boxShadow: '0 4px 12px -4px var(--accent)',
          }}>
            <Icon name="send" size={15} stroke="var(--accentFg)" strokeWidth={2.2} />
          </div>
        </div>
      </div>
    </PhoneFrame>
  );
}

// ── 4. Scan QR ───────────────────────────────────────────────────
function MobileScan({ dark }) {
  return (
    <PhoneFrame dark={dark}>
      <div style={{
        flex: 1, position: 'relative', overflow: 'hidden',
        background: '#000',
      }}>
        {/* faux camera feed */}
        <div style={{
          position: 'absolute', inset: 0,
          background: 'radial-gradient(ellipse at 30% 20%, oklch(0.32 0.05 220), oklch(0.12 0.02 220) 70%)',
        }}/>
        {/* faux mac silhouette */}
        <div style={{
          position: 'absolute', left: '50%', top: '50%', transform: 'translate(-50%,-50%)',
          width: 200, height: 130, borderRadius: 8,
          background: 'linear-gradient(180deg, #2a2f38, #1a1d24)',
          border: '1px solid rgba(255,255,255,0.1)',
          boxShadow: '0 20px 60px rgba(0,0,0,0.6)',
        }}>
          <div style={{
            position: 'absolute', inset: '8px 8px 28px',
            borderRadius: 4, background: '#0d1117',
            display: 'grid', placeItems: 'center',
          }}>
            <div style={{
              width: 80, height: 80, padding: 4, borderRadius: 6,
              background: '#fff',
            }}>
              <FakeQR/>
            </div>
          </div>
        </div>

        {/* scanning area */}
        <div style={{
          position: 'absolute', left: '50%', top: '54%',
          transform: 'translate(-50%,-50%)',
          width: 244, height: 244, borderRadius: 28,
          border: '2px solid rgba(255,255,255,0.0)',
          boxShadow: '0 0 0 9999px rgba(0,0,0,0.55)',
        }}>
          {/* corner brackets */}
          {[
            { k: 'tl', pos: { top: -2, left: -2 },    bw: '3px 0 0 3px', br: '10px 0 0 0' },
            { k: 'tr', pos: { top: -2, right: -2 },   bw: '3px 3px 0 0', br: '0 10px 0 0' },
            { k: 'bl', pos: { bottom: -2, left: -2 }, bw: '0 0 3px 3px', br: '0 0 0 10px' },
            { k: 'br', pos: { bottom: -2, right: -2 },bw: '0 3px 3px 0', br: '0 0 10px 0' },
          ].map(c => (
            <div key={c.k} style={{
              position: 'absolute', width: 28, height: 28, ...c.pos,
              borderColor: 'var(--accent)', borderStyle: 'solid',
              borderWidth: c.bw, borderRadius: c.br,
              boxShadow: '0 0 12px var(--accent)',
            }}/>
          ))}
          {/* scan laser */}
          <div style={{
            position: 'absolute', left: 8, right: 8, height: 2,
            background: 'linear-gradient(90deg, transparent, var(--accent), transparent)',
            boxShadow: '0 0 12px var(--accent)',
            animation: 'cc-scan 2.4s ease-in-out infinite',
          }}/>
        </div>

        {/* top hint */}
        <div style={{
          position: 'absolute', top: 24, left: 20, right: 20, zIndex: 2,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <div style={{
            width: 36, height: 36, borderRadius: '50%',
            background: 'rgba(255,255,255,0.1)',
            backdropFilter: 'blur(20px)',
            display: 'grid', placeItems: 'center', color: '#fff',
          }}><Icon name="arrowLeft" size={16}/></div>
          <div style={{
            flex: 1, padding: '10px 16px', borderRadius: 100,
            background: 'rgba(255,255,255,0.08)',
            backdropFilter: 'blur(20px)',
            border: '1px solid rgba(255,255,255,0.1)',
            fontSize: 13, color: '#fff',
          }}>
            将相机对准 Mac 上的 QR 码
          </div>
        </div>

        {/* bottom panel */}
        <div style={{
          position: 'absolute', left: 16, right: 16, bottom: 16, zIndex: 2,
          padding: 16, borderRadius: 18,
          background: 'rgba(15,17,22,0.7)',
          backdropFilter: 'blur(24px)',
          border: '1px solid rgba(255,255,255,0.1)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <PulseDot color="var(--accent)" size={8} />
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, fontWeight: 700, color: '#fff' }}>
                正在搜索 QR 码…
              </div>
              <div style={{ fontSize: 11.5, color: 'rgba(255,255,255,0.55)' }}>
                cc-anywhere · v0.4.2
              </div>
            </div>
            <div style={{
              padding: '8px 14px', borderRadius: 100,
              background: 'rgba(255,255,255,0.1)',
              color: '#fff', fontSize: 12.5, fontWeight: 600,
            }}>手动输入</div>
          </div>
        </div>
      </div>
    </PhoneFrame>
  );
}

// ── 5. Settings ─────────────────────────────────────────────────
function MobileSettings({ dark }) {
  return (
    <PhoneFrame dark={dark}>
      <div style={{
        padding: '4px 16px 8px', flexShrink: 0,
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        <div style={{
          width: 34, height: 34, borderRadius: '50%',
          background: 'var(--bgInset)', display: 'grid', placeItems: 'center',
          color: 'var(--textMuted)',
        }}><Icon name="arrowLeft" size={16}/></div>
        <div style={{
          fontSize: 17, fontWeight: 700, color: 'var(--text)',
        }}>设置</div>
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '8px 16px 16px' }}>
        {/* Device card */}
        <div style={{
          padding: '16px 16px 18px', borderRadius: 18,
          background: 'linear-gradient(135deg, var(--accentSoft), var(--bgElev))',
          border: '1px solid var(--line)',
          marginBottom: 18, position: 'relative', overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', right: -30, top: -30, width: 140, height: 140,
            borderRadius: '50%', background: 'var(--accent)', opacity: 0.15, filter: 'blur(20px)',
          }}/>
          <SectionLabel>本机</SectionLabel>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 8 }}>
            <div style={{
              width: 46, height: 46, borderRadius: 12,
              background: 'linear-gradient(135deg, var(--accent), oklch(0.55 0.18 280))',
              display: 'grid', placeItems: 'center', color: '#fff',
              boxShadow: '0 6px 16px -6px var(--accent)',
            }}>
              <Icon name="devices" size={20} strokeWidth={2} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 16, fontWeight: 700, color: 'var(--text)' }}>
                Pixel 8 Pro
              </div>
              <div style={{ fontSize: 11.5, color: 'var(--textMuted)', fontFamily: '"JetBrains Mono", ui-monospace' }}>
                Android 14 · sub_token …7a3f
              </div>
            </div>
            <Icon name="edit" size={16} stroke="var(--textMuted)" />
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <StatusPill color="var(--success)" accent>在线 · 38ms</StatusPill>
            <StatusPill icon={<Icon name="lock" size={11} stroke="var(--textMuted)" />}>TLS 1.3</StatusPill>
          </div>
        </div>

        <SectionLabel style={{ padding: '0 4px', marginBottom: 8 }}>Server</SectionLabel>
        <div style={{
          borderRadius: 14, background: 'var(--bgElev)',
          border: '1px solid var(--line)', overflow: 'hidden', marginBottom: 18,
        }}>
          {[
            { i: 'wifi', l: 'Server 地址', v: 'cc.example.com:8443' },
            { i: 'cpu', l: 'agent_id', v: 'agt_4f2c·8a91' },
            { i: 'history', l: '查看连接日志' },
          ].map((row, i, a) => (
            <div key={row.l} style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px',
              borderBottom: i < a.length - 1 ? '1px solid var(--line)' : 'none',
            }}>
              <div style={{ color: 'var(--accent)' }}>
                <Icon name={row.i} size={16} />
              </div>
              <span style={{ flex: 1, fontSize: 14, color: 'var(--text)' }}>{row.l}</span>
              {row.v && <span style={{
                fontSize: 12, color: 'var(--textMuted)',
                fontFamily: '"JetBrains Mono", ui-monospace',
              }}>{row.v}</span>}
              <Icon name="chevronRight" size={14} stroke="var(--textFaint)" />
            </div>
          ))}
        </div>

        <SectionLabel style={{ padding: '0 4px', marginBottom: 8 }}>外观</SectionLabel>
        <div style={{
          borderRadius: 14, background: 'var(--bgElev)',
          border: '1px solid var(--line)', overflow: 'hidden', marginBottom: 18,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px',
            borderBottom: '1px solid var(--line)',
          }}>
            <Icon name={dark ? 'moon' : 'sun'} size={16} stroke="var(--accent)" />
            <span style={{ flex: 1, fontSize: 14, color: 'var(--text)' }}>外观模式</span>
            <div style={{ display: 'flex', gap: 0, padding: 2, borderRadius: 100, background: 'var(--bgInset)' }}>
              {['浅色', '深色', '跟随系统'].map(l => (
                <div key={l} style={{
                  fontSize: 11.5, fontWeight: 600,
                  padding: '5px 10px', borderRadius: 100,
                  background: (dark ? l === '深色' : l === '浅色') ? 'var(--accent)' : 'transparent',
                  color: (dark ? l === '深色' : l === '浅色') ? 'var(--accentFg)' : 'var(--textMuted)',
                }}>{l}</div>
              ))}
            </div>
          </div>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px',
          }}>
            <Icon name="bell" size={16} stroke="var(--accent)" />
            <span style={{ flex: 1, fontSize: 14, color: 'var(--text)' }}>tool_use 推送通知</span>
            <div style={{
              width: 40, height: 24, borderRadius: 12,
              background: 'var(--accent)', position: 'relative',
            }}>
              <div style={{
                position: 'absolute', top: 2, right: 2, width: 20, height: 20,
                borderRadius: '50%', background: '#fff',
              }}/>
            </div>
          </div>
        </div>

        <div style={{
          padding: '14px 16px', borderRadius: 14,
          border: '1px solid color-mix(in oklab, var(--danger) 40%, transparent)',
          background: 'color-mix(in oklab, var(--danger) 6%, transparent)',
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <Icon name="logout" size={16} stroke="var(--danger)" />
          <span style={{ flex: 1, fontSize: 14, fontWeight: 600, color: 'var(--danger)' }}>
            解绑此设备
          </span>
          <Icon name="chevronRight" size={14} stroke="var(--danger)" />
        </div>

        <div style={{
          textAlign: 'center', fontSize: 11, color: 'var(--textFaint)',
          marginTop: 18, fontFamily: '"JetBrains Mono", ui-monospace',
        }}>
          v0.4.2 · build 2026.05.13
        </div>
      </div>
    </PhoneFrame>
  );
}

Object.assign(window, {
  MobileWelcome, MobileTabList, MobileChat, MobileScan, MobileSettings,
});
