% Plot a damped sine wave and mark its largest peak.
% Run as a script; it takes no arguments.

t = linspace(0, 10, 500);
y = exp(-0.3 * t) .* sin(2 * pi * t);

[peak, index] = max(y);

plot(t, y);
hold on;
plot(t(index), peak, 'ro');
hold off;

xlabel('Time (s)');
ylabel('Amplitude');
title(sprintf('Damped sine wave, peak %.2f at t = %.2f s', peak, t(index)));
