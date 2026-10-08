# ShinyReact prototype behavior

- The page identifies itself as a technical prototype for Family finances.
- React owns the account-slot selector and sends its value to the R server.
- The upload control is a genuine Shiny file input hosted inside React.
- Before a file is selected, the import-preview JSON reports `waiting`.
- Selecting a valid export returns coverage and aggregate new/known counts.
- Selecting a malformed export returns the complete blocking problem list.
- Previewing a file never writes an import or transaction.
- The preview reminds the user to verify the account slot and use complete-day exports.
- Text entered in the bridge check returns from R as acknowledged JSON.
- Output recalculation keeps the previous preview visible with reduced emphasis.
