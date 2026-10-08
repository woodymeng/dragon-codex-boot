"""Generate calls to the existing synchronous XCTest methods, failing closed on new shapes."""
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text()
classes = re.split(r"final class (\w+): XCTestCase \{", source)
calls = []
for index in range(1, len(classes), 2):
    suite, body = classes[index:index + 2]
    methods = re.findall(r"    func (test\w+)\(\)( throws)? \{", body)
    if len(methods) != len(re.findall(r"\bfunc test", body)):
        raise SystemExit("Unsupported test signature; update the CLT runner before proceeding.")
    for method, throws in methods:
        invocation = f"{suite}().{method}()"
        if throws:
            invocation = "try " + invocation
        calls.append(f'runTest("{suite}.{method}") {{ {invocation} }}')
if not calls or len(calls) != len(re.findall(r"\bfunc test", source)):
    raise SystemExit("Test discovery mismatch; no tests may be silently skipped.")
Path(sys.argv[2]).write_text("import Foundation\n" + "\n".join(calls) + "\nfinishTests()\n")
