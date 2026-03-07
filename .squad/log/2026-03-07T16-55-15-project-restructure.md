# Session: Project Restructure (AVM Modernization)
**Timestamp:** 2026-03-07T16:55:15Z  
**Task:** Restructure two samples into self-contained azd-compatible projects with AVM-based Bicep

**Outcome:** ✅ Complete
- durable-text-analysis/ and ffmpeg-image-processing/ restructured
- Each sample has own azure.yaml, infra/main.bicep (AVM-based), src/, scripts/
- Shared infra/ directory removed; per-sample modular Bicep replaces it
- Both samples ready for `azd up` deployment and Azure Samples submission
