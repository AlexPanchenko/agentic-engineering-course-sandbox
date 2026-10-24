#!/usr/bin/env python3
"""
calculate_cost.py - Calculate prompt token usage and 1000-request cost for Sonnet 4.6.

Formula:
  Sonnet 4.6: $3.00 / 1M input tokens, $15.00 / 1M output tokens.
  Cost per request = (input_tokens * 3.0 / 1_000_000) + (output_tokens * 15.0 / 1_000_000)
  Total cost (1000 requests) = Cost per request * 1000
"""

import argparse
import os
import sys
from dotenv import load_dotenv

# Try loading from current directory, then from the .env next to this script
load_dotenv()
if not os.environ.get("ANTHROPIC_API_KEY"):
    load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

MODEL_SONNET = "claude-sonnet-4-6"

# Pricing per 1 Million tokens (Sonnet 4.6)
SONNET_INPUT_PRICE_PER_M = 3.00
SONNET_OUTPUT_PRICE_PER_M = 15.00


def get_anthropic_client():
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(
            "Error: ANTHROPIC_API_KEY is not set.\n"
            "Please export ANTHROPIC_API_KEY or create a .env file with your key.",
            file=sys.stderr,
        )
        sys.exit(1)
    try:
        from anthropic import Anthropic
        return Anthropic(api_key=api_key)
    except ImportError:
        print(
            "Error: 'anthropic' package is not installed.\n"
            "Run: pip install anthropic python-dotenv",
            file=sys.stderr,
        )
        sys.exit(1)


def count_input_tokens(client, prompt: str, system: str = "", model: str = MODEL_SONNET) -> int:
    kwargs = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
    }
    if system:
        kwargs["system"] = system

    result = client.messages.count_tokens(**kwargs)
    return result.input_tokens


def measure_via_api(client, prompt: str, system: str = "", model: str = MODEL_SONNET, max_tokens: int = 1024):
    kwargs = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }
    if system:
        kwargs["system"] = system

    response = client.messages.create(**kwargs)
    input_tokens = response.usage.input_tokens
    output_tokens = response.usage.output_tokens
    reply_text = "".join(
        block.text for block in response.content if getattr(block, "type", "") == "text"
    )
    return input_tokens, output_tokens, reply_text


def calculate_cost(input_tokens: int, output_tokens: int, num_requests: int = 1000):
    cost_per_req_input = (input_tokens / 1_000_000.0) * SONNET_INPUT_PRICE_PER_M
    cost_per_req_output = (output_tokens / 1_000_000.0) * SONNET_OUTPUT_PRICE_PER_M
    cost_per_req = cost_per_req_input + cost_per_req_output

    total_cost_input = cost_per_req_input * num_requests
    total_cost_output = cost_per_req_output * num_requests
    total_cost = cost_per_req * num_requests

    return {
        "cost_per_req_input": cost_per_req_input,
        "cost_per_req_output": cost_per_req_output,
        "cost_per_req": cost_per_req,
        "total_cost_input": total_cost_input,
        "total_cost_output": total_cost_output,
        "total_cost": total_cost,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Count prompt tokens, estimate/measure output, and calculate cost for Sonnet 4.6."
    )
    parser.add_argument(
        "prompt_arg",
        nargs="?",
        default="",
        help="Prompt text (optional if provided via flag, file, or stdin)",
    )
    parser.add_argument(
        "-p", "--prompt",
        default="",
        help="Prompt text",
    )
    parser.add_argument(
        "-f", "--file",
        help="Path to file containing prompt text",
    )
    parser.add_argument(
        "-s", "--system",
        default="",
        help="Optional system prompt",
    )
    parser.add_argument(
        "-m", "--measure",
        action="store_true",
        help="Execute API call (messages.create) to measure exact output tokens instead of estimating",
    )
    parser.add_argument(
        "-e", "--estimate-output",
        type=int,
        default=200,
        help="Estimated output token count when not measuring via API (default: 200)",
    )
    parser.add_argument(
        "-n", "--requests",
        type=int,
        default=1000,
        help="Number of requests to calculate cost for (default: 1000)",
    )
    parser.add_argument(
        "--model",
        default=MODEL_SONNET,
        help=f"Model identifier (default: {MODEL_SONNET})",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=1024,
        help="Max output tokens when using --measure (default: 1024)",
    )

    args = parser.parse_args()

    # Determine prompt text
    prompt = ""
    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            prompt = f.read().strip()
    elif args.prompt:
        prompt = args.prompt.strip()
    elif args.prompt_arg:
        prompt = args.prompt_arg.strip()
    elif not sys.stdin.isatty():
        prompt = sys.stdin.read().strip()

    if not prompt:
        prompt = "Поясни коротко в трьох реченнях, що таке LLM механіка та як формуються токени."
        print(f"⚠️  Промпт не вказано. Використовуємо дефолтний приклад:\n   \"{prompt}\"\n")

    client = get_anthropic_client()

    print("=" * 64)
    print(f" Модель: {args.model} (Sonnet 4.6)")
    print(f" Тарифи: Input: ${SONNET_INPUT_PRICE_PER_M:.2f}/1M | Output: ${SONNET_OUTPUT_PRICE_PER_M:.2f}/1M")
    print(f" Кількість запитів: {args.requests:,}")
    print("=" * 64)

    # Preview prompt
    preview = prompt if len(prompt) <= 120 else prompt[:117] + "..."
    print(f"📝 Промпт: \"{preview}\"")
    if args.system:
        sys_prev = args.system if len(args.system) <= 80 else args.system[:77] + "..."
        print(f"⚙️  System : \"{sys_prev}\"")
    print("-" * 64)

    if args.measure:
        print("🚀 Вимірювання через API (messages.create)...")
        input_tokens, output_tokens, reply_text = measure_via_api(
            client=client,
            prompt=prompt,
            system=args.system,
            model=args.model,
            max_tokens=args.max_tokens,
        )
        print("✅ Отримано відповідь:")
        print(f"   {reply_text.strip()}")
        print("-" * 64)
        output_source = "фактичний вимір через API"
    else:
        print("🔍 Підрахунок вхідних токенів через messages.count_tokens...")
        input_tokens = count_input_tokens(
            client=client,
            prompt=prompt,
            system=args.system,
            model=args.model,
        )
        output_tokens = args.estimate_output
        output_source = f"оцінка ({output_tokens} токенів)"

    costs = calculate_cost(input_tokens, output_tokens, args.requests)

    print(f"📊 Результати токенізації:")
    print(f"   • Input tokens  : {input_tokens:,} токенів (через count_tokens)")
    print(f"   • Output tokens : {output_tokens:,} токенів ({output_source})")
    print()
    print(f"🧮 Формула вартості для {args.requests:,} запитів:")
    print(f"   Input cost  = ({input_tokens} / 1,000,000) * ${SONNET_INPUT_PRICE_PER_M:.2f} * {args.requests} = ${costs['total_cost_input']:.4f}")
    print(f"   Output cost = ({output_tokens} / 1,000,000) * ${SONNET_OUTPUT_PRICE_PER_M:.2f} * {args.requests} = ${costs['total_cost_output']:.4f}")
    print(f"   --------------------------------------------------------")
    print(f"   За 1 запит  : ${costs['cost_per_req']:.6f}")
    print(f"   За {args.requests:,} запитів: ${costs['total_cost']:.4f} (точна сума: ${costs['total_cost']:.2f})")
    print("=" * 64)
    print(f"💰 РАЗОМ: ${costs['total_cost']:.4f} USD")
    print("=" * 64)


if __name__ == "__main__":
    main()
