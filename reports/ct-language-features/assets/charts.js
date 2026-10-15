// Phase progress chart for the ct language-feature report.
(function () {
  var style = getComputedStyle(document.documentElement);
  var accent  = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink     = style.getPropertyValue('--ink').trim();
  var muted   = style.getPropertyValue('--muted').trim();
  var rule    = style.getPropertyValue('--rule').trim();
  var bg2     = style.getPropertyValue('--bg2').trim();

  var el = document.getElementById('chart-phases');
  if (!el || typeof echarts === 'undefined') return;

  // Completion is a share of each phase's own landed sub-stages. Phase 1 is an
  // estimate: 1.0-1.7 and 1.9 have landed, 1.8 moved to Phase 3, three known
  // gaps remain (-I, cross-unit trait objects, foo.h.ct semantics).
  var rows = [
    { name: 'Phase 0 · 完整 OO',        value: 100 },
    { name: 'Phase 0.1 · 缺陷修复',      value: 100 },
    { name: 'Phase 0.2 · 接口多态',      value: 100 },
    { name: 'Phase 1 · 模块化/内存/诊断', value: 90  },
    { name: 'Phase 2 · AutoDrop/分析',   value: 0   },
    { name: 'Phase 3 · 自举/增量',       value: 0   }
  ];

  var chart = echarts.init(el, null, { renderer: 'svg' });
  chart.setOption({
    animation: false,
    grid: { left: 8, right: 56, top: 16, bottom: 28, containLabel: true },
    tooltip: {
      trigger: 'item',
      appendToBody: true,
      formatter: function (p) { return p.name + '<br/>落地进度：' + p.value + '%'; }
    },
    xAxis: {
      type: 'value',
      max: 100,
      axisLabel: { color: muted, formatter: '{value}%', fontSize: 11 },
      axisLine: { lineStyle: { color: rule } },
      splitLine: { lineStyle: { color: rule, type: 'dashed' } }
    },
    yAxis: {
      type: 'category',
      inverse: true,
      data: rows.map(function (r) { return r.name; }),
      axisLabel: { color: ink, fontSize: 12 },
      axisLine: { lineStyle: { color: rule } },
      axisTick: { show: false }
    },
    series: [{
      type: 'bar',
      barWidth: '52%',
      data: rows.map(function (r) {
        return {
          value: r.value,
          itemStyle: {
            color: r.value === 100 ? accent : (r.value > 0 ? accent2 : bg2),
            borderRadius: [0, 3, 3, 0]
          }
        };
      }),
      label: {
        show: true,
        position: 'right',
        color: ink,
        fontSize: 11,
        fontWeight: 700,
        formatter: '{c}%'
      }
    }]
  });

  window.addEventListener('resize', function () { chart.resize(); });
})();
