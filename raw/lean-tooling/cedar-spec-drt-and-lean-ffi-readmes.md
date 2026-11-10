# cedar-spec: cedar-drt README and cedar-lean-ffi README

> Source: https://github.com/cedar-policy/cedar-spec/tree/main/cedar-drt ; https://github.com/cedar-policy/cedar-spec/tree/main/cedar-lean-ffi
> Collected: 2026-11-10
> Published: Unknown (fetched 2026-11-10)

## cedar-drt/README.md
# Cedar DRT

This folder contains code for fuzzing, property-based testing, and differential testing of Cedar.
See the README in the toplevel directory `..` for instructions on how to run.

## Available fuzz targets

The table below lists all available fuzz targets, including which component of the code they test and whether they perform differential testing of the Rust code against the Lean spec (DRT) or property-based testing of the Rust code (PBT). The latter properties are subdivided in the table as _round trip_ properties and _general_ properties.

| Name | Component(s) tested | Type | Description |
| ----------- | ----------- | ----------- | ----------- |
| [`abac-type-directed`](fuzz/fuzz_targets/abac-type-directed.rs) | Authorizer | DRT | Diff test authorizer on ABAC policies using (mostly) well-typed inputs |
| [`abac`](fuzz/fuzz_targets/abac.rs) | Authorizer | DRT | Diff test authorizer on ABAC policies |
| [`eval-type-directed`](fuzz/fuzz_targets/eval-type-directed.rs) | Evaluator | DRT | Diff test evaluator on (mostly) well-typed expressions |
| [`rbac-authorizer`](fuzz/fuzz_targets/rbac-authorizer.rs) | Authorizer | DRT | Test for correct authorization responses over a set of simple policies |
| [`rbac`](fuzz/fuzz_targets/rbac.rs) | Authorizer | DRT | Diff test authorizer on sets of RBAC policies, including template instantiations |
| [`validation-drt-type-directed`](fuzz/fuzz_targets/validation-drt-type-directed.rs) | Validator | DRT | Diff test validation using (mostly) well-typed inputs |
| [`validation-drt`](fuzz/fuzz_targets/validation-drt.rs) | Validator | DRT | Diff test validation |
| [`entity-validation`](fuzz/fuzz_targets/entity-validation.rs) | Entity Validator | DRT | Diff test entity validation |
| [`request-validation`](fuzz/fuzz_targets/request-validation.rs) | Request Validator | DRT | Diff test request validation |
| [`partial-schema-validation-drt`](fuzz/fuzz_targets/partial-schema-validation-drt.rs) | Entity and Request Validator (RFC 116) | DRT | Diff test entity and request validation against a schema that declares some entity types and actions `external` |
| [`partial-schema-link-drt`](fuzz/fuzz_targets/partial-schema-link-drt.rs) | Schema linker (RFC 116) | DRT | Diff test successful and rejected links between generated partial schemas |
| [`partial-schema-link-order-independence-pbt`](fuzz/fuzz_targets/partial-schema-link-order-independence-pbt.rs) | Schema linker (RFC 116) | PBT | Test that linking is independent of the order of its inputs, on schemas parsed from arbitrary JSON |
| [`tpe-is-authorized-drt`](fuzz/fuzz_targets/tpe-is-authorized-drt.rs) | TPE (partial authorization) | DRT | Diff test Rust and Lean TPE is_authorized API: decisions, policy categorizations, and residual expressions |
| [`tpe-residual-reauthorize-drt`](fuzz/fuzz_targets/tpe-residual-reauthorize-drt.rs) | TPE (reauthorization of arbitrary residuals) | DRT | Diff test concrete evaluation of a generated residual. The model walks the residual directly; Rust projects it to an `Expr` and evaluates that, so this compares the two routes `reauthorize` and `Residual.evaluate` take |
| [`partial-entity-validation-drt`](fuzz/fuzz_targets/partial-entity-validation-drt.rs) | TPE (partial entity validator) | DRT | Diff test whether partial entities are valid for a schema |
| [`partial-entity-consistency-drt`](fuzz/fuzz_targets/partial-entity-consistency-drt.rs) | TPE (partial entity validator) | DRT | Diff test whether partial entities are consistent with concrete entities |
| [`partial-request-validation-drt`](fuzz/fuzz_targets/partial-request-validation-drt.rs) | TPE (partial request validator) | DRT | Diff test whether a partial request is valid for a schema |
| [`partial-request-consistency-drt`](fuzz/fuzz_targets/partial-request-consistency-drt.rs) | TPE (partial request validator) | DRT | Diff test whether a partial request is consistent with a concrete request |
|  |  |  |  |
| [`formatter`](fuzz/fuzz_targets/formatter.rs) | Policy formatter, Pretty printer, Parser | PBT | Test round trip property: parse ∘ format ∘ pretty-print == id for ASTs |
| [`formatter-bytes`](fuzz/fuzz_targets/formatter-bytes.rs) | Policy formatter, Parser | PBT | The same as `formatter`, but we start with an arbitrary string instead of pretty-printing a policy AST |
| [`json-schema-roundtrip`](fuzz/fuzz_targets/json-schema-roundtrip.rs) | Schema parser | PBT | Test round trip property: parse ∘ pretty-print ∘ parse-json ∘ print-json == id for schemas
| [`roundtrip`](fuzz/fuzz_targets/roundtrip.rs) | Pretty printer, Parser, Conversion to JSON | PBT | Test round trip property: parse ∘ pretty-print == deserialize ∘ serialize == id for policy ASTs |
| [`policy-set-roundtrip`](fuzz/fuzz_targets/policy-setroundtrip.rs) | Pretty printer, Parser, Conversion to JSON | PBT | Test round trip property: parse ∘ pretty-print == deserialize ∘ serialize == id for a policy set ASTs
| [`schema-roundtrip`](fuzz/fuzz_targets/schema-roundtrip.rs) | Schema parser | PBT | Test round trip property: parse ∘ pretty-print == id for schemas
| [`convert-schema-json-to-human`](fuzz/fuzz_targets/convert-schema-json-to-human.rs) | Schema parser | PBT | Test we can convert all human schemas to equivalent JSON. parse == parse-json ∘ print-json ∘ parse
| [`convert-schema-human-to-json`](fuzz/fuzz_targets/convert-schema-human-to-json.rs) | Schema parser | PBT | Test we can convert all JSON schemas to an equivalent human format schema. parse-json == parse ∘ pretty-print ∘ parse-json
| [`convert-policy-cedar-to-json`](fuzz/fuzz_targets/convert-policy-cedar-to-json.rs) | Parser, Conversion to JSON | PBT | Test we can convert all policies to an equivalent EST.  parse-ast ∘ parse-cst == deserialize ∘ serialize ∘ parse-cst
| [`convert-policy-json-to-cedar`](fuzz/fuzz_targets/convert-policy-json-to-cedar.rs) | Parser, JSON Parser | PBT | Test we can convert all EST to an equivalent policy in the human-readable cedar syntax. deserialize == parse-ast ∘ pretty-print ∘ deserialize
| [`roundtrip-entities`](fuzz/fuzz_targets/roundtrip-entities.rs) | Entity parser | PBT | Test round trip property for entity data. parse-entity-json ∘ serialize-entity == id for entities |
| [`roundtrip-entities-bytes`](fuzz/fuzz_targets/roundtrip-entities.rs) | Entity parser | PBT | Test the same round trip property for entity data, starting from an arbitrary string instead of generating the entities data structure |
| [`pst-ast-roundtrip`](fuzz/fuzz_targets/pst-ast-roundtrip.rs) | PST ↔ AST conversion | PBT | Test idempotency: PST → AST → PST → AST → PST stabilizes after one normalization pass |
| [`pst-est-roundtrip`](fuzz/fuzz_targets/pst-est-roundtrip.rs) | PST ↔ EST conversion | PBT | Test round trip property: PST → EST → PST == id for templates |
| [`pst-policyset-text-roundtrip`](fuzz/fuzz_targets/pst-policyset-text-roundtrip.rs) | PST policy set conversion through API | PBT | Test round trip property: PST policy set -> PolicySet → cedar text → PolicySet -> PST == id with explicit policy id management, and through public API |
| [`pst-policyset-json-roundtrip`](fuzz/fuzz_targets/pst-policyset-json-roundtrip.rs) | PST policy set conversion through API | PBT | Test round trip property: PST policy set -> PolicySet → JSON → PolicySet -> PST == id with explicit policy id management, and through public API |
|  |  |  |  |
| [`simple-parser`](fuzz/fuzz_targets/simple-parser.rs) |  Parser | PBT | Test that parsing doesn't crash with random input strings |
| [`validation-pbt`](fuzz/fuzz_targets/validation-pbt.rs) | Validator | PBT | Test that validated policies do not result in type errors |
| [`validation-pbt-type-directed`](fuzz/fuzz_targets/validation-pbt-type-directed.rs) | Validator | PBT | Test that validated policies do not result in type errors using (mostly) well-typed inputs |
| [`entity-manifest-drt-type-directed`](fuzz/fuzz_targets/entity-slicing-pbt-type-directed.rs) | Entity Slicing | DRT | Test that entity slicing produces the same authorization response as without it. |
| [`wildcard-matching`](fuzz/fuzz_targets/wildcard-matching.rs) | String matching algorithm used for the `like` operator | PBT | Test algorithm against a regex-based implementation |
| [`tc-repair-equivalence`](fuzz/fuzz_targets/tc-repair-equivalence.rs) | Entity transitive closure (`repair_tc` vs `compute_tc`) | PBT | Test that incrementally repairing the transitive closure of an entity graph (`repair_tc` after adding edges) agrees with recomputing it from scratch (`compute_tc`), on both cycle detection and the resulting ancestor sets |
| [`entities-upsert-equivalence`](fuzz/fuzz_targets/entities-upsert-equivalence.rs) | Entity store incremental update (`Entities::upsert_entities`) | PBT | Test that applying a batch of entity upserts to a store agrees with rebuilding the store from scratch via `Entities::from_entities`, comparing ancestor sets and cycle detection. Catches the stale-ancestor bug fixed in [cedar#2628](https://github.com/cedar-policy/cedar/pull/2628) where a node repeated in one batch kept a dropped parent's ancestors |

## Generating corpus tests

When using the `abac` or `abac-type-directed` targets, you can set `DUMP_TEST_DIR` and `DUMP_TEST_NAME` to have the fuzzer write out inputs in the format used by our [integration tests](https://github.com/cedar-policy/cedar/tree/main/cedar-integration-tests).
The `create_corpus.sh` script will run the fuzzer for a set amount of time and then write the (minimized) corpus inputs into a folder using the integration test format.
You can adjust the script's behavior using the following environment variables:

* `FUZZ_TARGET`: `abac` or `abac-type-directed` (default = `abac`)
* `TIMEOUT`: how long to run (default = 15m)
* `JOBS`: number of jobs (default = 4)
* `DUMP_DIR`: where to write the results (default = `./corpus_tests`)

## Debugging build failures

If you run into weird build issues,
1. Make sure you have run `source set_env_vars.sh`, which sets all the environment variables needed to run the Lean definitional code.
2. Make sure you have built the Lean library with `( cd ../cedar-lean && ../cedar-drt/build_lean_lib.sh )`. See the [cedar-lean README](../cedar-lean/README.md) if this command doesn't work.
3. Try a `cargo clean` and rebuild.
4. If the steps above don't help, then file [an issue](https://github.com/cedar-policy/cedar-spec/issues).

If everything builds, but the integration tests are failing, then it may be helpful to set `RUST_BACKTRACE=1` and run `cargo test -- --nocapture` to print additional test information.

## Running integration tests

The integration tests are run by default in CI (e.g., as a part of each pull request), but you can also run them locally.
In order to do this, you need to have the [`cedar`](https://github.com/cedar-policy/cedar) and [`cedar-integration-tests`](https://github.com/cedar-policy/cedar-integration-tests) repositories cloned locally.
`cedar` should be in the toplevel directory (so `../cedar`) and `cedar-integration-tests` should be in the `cedar` directory (so `../cedar/cedar-integration-tests`).
Then, run `cargo test --features "integration-testing"`.

```bash
# starting in the top-level directory (..)
git clone --depth 1 https://github.com/cedar-policy/cedar
cd cedar
rm -rf cedar-integration-tests
git clone --depth 1 https://github.com/cedar-policy/cedar-integration-tests
cd cedar-integration-tests
tar xzf corpus-tests.tar.gz
cd ../../cedar-drt
cargo test --features "integration-testing"
```

## cedar-lean-ffi/README.md
# Cedar Lean FFI (Rust Bindings of Cedar Lean Formalization)

This directory contains Rust bindings for interacting with the Lean formalization of Cedar. This FFI assumes all inputs for `Policy`s, `PolicySet`s, `Entities`, `Schema`s, `Request`s are represented using [`Cedar`](https://github.com/cedar-policy/cedar) public API types. This FFI makes use of Cedar's Protobuf feature to convert Cedar types in Rust to the corresponding type within the Lean formalization.

## Build

### Prerequisites:

#### Install Lean
For more details read about Lean's version manager [elan](https://github.com/leanprover/elan).

```
curl https://elan.lean-lang.org/elan-init.sh -sSf | sh
```

#### Install cvc5 (>= v1.0.5)
The analysis features provided by this CLI requires a local install of [cvc5](https://github.com/cvc5/cvc5) with version [1.0.5](https://github.com/cvc5/cvc5/releases/tag/cvc5-1.0.5) or greater.

Once you install cvc5. Export the following Environment variable which allows this CLI to know where cvc5 is installed. Consider adding the export to your `~/.bashrc` or `~/.profile` so that the environment variable is exported to all new terminal sessions.

```
export CVC5=<PATH-TO-CVC5-EXECUTABLE>
```

#### Install Rust

This CLI is written in Rust and uses Lean's foreign function interface to call the relevant parts of the Cedar lean formalization.

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

#### Install Protoc

This CLI uses Protobuf for serializing Cedar data structures between the Rust frontend and Lean backend of this CLI.

Download and install Protobuf. The code has been tested with [Protobuf v29.3](https://github.com/protocolbuffers/protobuf/releases/tag/v29.3). If you are using Linux (on x86_64 arch) and wish to install protobuf to `/usr/local/` you can use the following instructions to install protobuf. For more information see the official [Protobuf installation page](https://github.com/protocolbuffers/protobuf#protobuf-compiler-installation).

```
curl -OL https://github.com/protocolbuffers/protobuf/releases/download/v29.3/protoc-29.3-linux-x86_64.zip
unzip protoc-29.3-linux-x86_64.zip
cp bin/protoc /usr/local/bin/
cp -r include/google/ /usr/local/include/
```

### Build this Library

Use the following commands to build the `cedar-lean-ffi` Library.

```
cd cedar-spec/cedar-lean-ffi        # Enter this directory
source set_env_vars.sh              # Update environment variables with Lean's library location
./build_lean_lib.sh                 # Build the Lean model of Cedar
cargo build                         # Build this library
```

Consider adding `source <path-to-cedar-spec>/cedar-lean-ffi/set_env_vars.sh` to your `~/.bashrc` or `~/.profile` to ensure Lean's library path is automatically exported in all new terminal sessions.

If you try to run an executable linked with this library and get the error `error while loading shared libraries: libleanshared.so: cannot open shared object file: No such file or directory` you need to run `source set_env_vars.sh`.
