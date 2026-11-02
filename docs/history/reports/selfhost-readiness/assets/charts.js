// assets/charts.js — report visuals (ECharts chart + Mermaid diagrams)
(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();

  // --- Chart: test-suite growth ---
  var el = document.getElementById('chart-tests');
  if (el && window.echarts) {
    var labels = ['Phase 1.7 泄漏警告', '1.7 测试补全', 'Phase 1.9c 及后续', '本轮自举收口'];
    var values = [92, 116, 143, 146];
    var chart = echarts.init(el, null, { renderer: 'svg' });
    chart.setOption({
      animation: false,
      grid: { left: 8, right: 16, top: 24, bottom: 8, containLabel: true },
      tooltip: { trigger: 'axis', appendToBody: true, axisPointer: { type: 'shadow' } },
      xAxis: {
        type: 'value',
        min: 0,
        max: 160,
        splitLine: { lineStyle: { color: rule } },
        axisLine: { lineStyle: { color: rule } },
        axisLabel: { color: muted }
      },
      yAxis: {
        type: 'category',
        data: labels,
        axisLine: { lineStyle: { color: rule } },
        axisTick: { show: false },
        axisLabel: { color: ink, fontSize: 12 }
      },
      series: [{
        type: 'bar',
        data: values.map(function (v, i) {
          return {
            value: v,
            itemStyle: { color: i === values.length - 1 ? accent2 : accent, borderRadius: [0, 4, 4, 0] }
          };
        }),
        barWidth: '48%',
        label: { show: true, position: 'right', color: ink, fontWeight: 600 }
      }]
    });
    window.addEventListener('resize', function () { chart.resize(); });
  }

  // --- Diagrams: Mermaid ---
  if (window.mermaid) {
    mermaid.initialize({ startOnLoad: true, theme: 'neutral', securityLevel: 'loose' });
  }
})();
