// Contracts to include in the registry
// Format: { name, file?, artifact? } where file/artifact default to name
// - name: registry key (used in API and filenames)
// - file: .sol filename in out/ (defaults to name)
// - artifact: contract name inside the .sol (defaults to name)
export const CONTRACTS = [
  { name: 'PriceProvider' },
  { name: 'PriceProviderL2' },
  { name: 'ProtectedPriceProvider' },
  { name: 'ProtectedPriceProviderL2' },
  { name: 'PriceProviderFactory' },
  { name: 'PriceProviderFactoryL2' },
  { name: 'CompressedOracle', file: 'CompressedOracle', artifact: 'CompressedOracleV1' },
  { name: 'PythOracle' },
  { name: 'ChainlinkOracle' },
];

// Maps contract names to their deployment key in networks.json
// networks: restrict to these chains only (default: all)
// exclude:  skip these chains
export const DEPLOYMENT_MAP = {
  PriceProviderFactory:   { key: 'factory', networks: ['ethereum'] },
  PriceProviderFactoryL2: { key: 'factory', exclude: ['ethereum'] },
  CompressedOracle:       { key: 'compressedOracle' },
  PythOracle:             { key: 'oracle', exclude: ['ethereum'] },
  ChainlinkOracle:        { key: 'dataStreamsOracle' },
};
