/**
 * The browser preview's canned answer: one reply that exercises every block
 * and inline type the renderer supports. Web preview only.
 *
 * Written with String.raw so TeX backslashes stay literal; `§` stands in for
 * a backtick, which String.raw cannot hold.
 */
export const demoShowcase = String.raw`<think>The user wants to see everything the renderer can draw. Cover reasoning, markdown structure, inline and display maths, environments, code in several languages, tables, and the failure cases.</think>

# Rendering showcase

*This is the web preview's sample answer. On a phone, a real model writes here.*

## Text and emphasis

Plain text, **bold**, *italic*, ***bold italic***, ~~strikethrough~~, §inline code§, and a [link to KaTeX](https://katex.org).
Currency is not maths: it costs $5 and then $10 more. An escaped dollar stays a dollar: \$20.

## Lists

1. Ordered item one
2. Ordered item two
   - Nested bullet
   - Another nested bullet
3. Ordered item three

- Unordered item
- Unordered item with **bold**

- [x] Task done
- [ ] Task to do

> A blockquote. Definitions and quoted passages from a paper render like this.

---

## Inline maths

Dollars: $E = mc^2$, $a^2 + b^2 = c^2$, $x_1, x_2$, $H_2O$.
Parentheses: \(\alpha + \beta = \gamma\), \(\sqrt{x}\), \(\frac{a}{b}\), \(\sum_{i=1}^{n} i\).
Symbols: $\pi \approx 3.14$, $x \leq y$, $A \cap B$, $\forall x \in \mathbb{R}$, $\nabla f$, $\infty$.

## Display maths

$$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$$

\[ \sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6} \]

$$\lim_{h \to 0} \frac{f(x+h) - f(x)}{h} = f'(x)$$

Matrix:

$$\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix} \begin{pmatrix} x \\ y \end{pmatrix} = \begin{pmatrix} 5 \\ 6 \end{pmatrix}$$

Aligned working:

\begin{aligned} (a+b)^2 &= (a+b)(a+b) \\ &= a^2 + 2ab + b^2 \end{aligned}

Cases:

$$f(x) = \begin{cases} x^2 & x \geq 0 \\ -x & x < 0 \end{cases}$$

Maxwell, with vectors:

$$\nabla \times \vec{E} = -\frac{\partial \vec{B}}{\partial t}$$

Broken TeX shows its source:

$$\frac{1}{\left( x$$

## Table

| Method | Time | Space | Stable |
|:---|:---:|---:|:---:|
| Merge sort | $O(n \log n)$ | $O(n)$ | Yes |
| Quick sort | $O(n \log n)$ | $O(\log n)$ | No |
| Heap sort | $O(n \log n)$ | $O(1)$ | No |

## Code

§§§python
from functools import lru_cache

@lru_cache(maxsize=None)
def fib(n: int) -> int:
    """Return the n-th Fibonacci number."""
    return n if n < 2 else fib(n - 1) + fib(n - 2)

print([fib(i) for i in range(10)])  # [0, 1, 1, 2, ...]
§§§

§§§typescript
type Turn = { role: 'user' | 'assistant'; content: string };

export function lastAnswer(turns: Turn[]): string | undefined {
  return [...turns].reverse().find((t) => t.role === 'assistant')?.content;
}
§§§

§§§cpp
#include <iostream>
int main() {
    for (int i = 0; i < 3; ++i) std::cout << "row " << i << '\n';
    return 0;
}
§§§

§§§json
{ "model": "phi-4-mini", "quant": "Q4_K_M", "offline": true, "context": 4096 }
§§§

§§§bash
echo $HOME && ls -la | grep ".gguf"
§§§

§§§
A fence with no language renders as plain monospace.
§§§

    Indented code also works.

**Answer:** every block type above is drawn natively, except display maths, which KaTeX typesets.`.replace(/§/g, '`');
