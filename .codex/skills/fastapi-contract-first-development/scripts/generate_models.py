#!/usr/bin/env python3
"""
Generate Pydantic models from OpenAPI specification.

Usage:
    python generate_models.py contracts/openapi.yaml app/models/
"""

import argparse


def generate_models(contract_path: str, output_dir: str) -> None:
    """Generate Pydantic models from OpenAPI contract."""
    print(f"📄 Reading contract from: {contract_path}")
    print(f"📁 Output directory: {output_dir}")

    # This is a placeholder - actual implementation would use datamodel-code-generator
    print("\n✨ To generate models, install and run:")
    print("   pip install datamodel-code-generator")
    print(f"   datamodel-codegen --input {contract_path} --output {output_dir}/generated.py")
    print("\nThe generated models will include:")
    print("  - Pydantic models for all schemas")
    print("  - Validation rules from the contract")
    print("  - Type hints and documentation")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Pydantic models from OpenAPI")
    parser.add_argument("contract", help="Path to OpenAPI contract file")
    parser.add_argument("output", help="Output directory for generated models")

    args = parser.parse_args()

    generate_models(args.contract, args.output)


if __name__ == "__main__":
    main()
