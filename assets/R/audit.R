library("rattle")

loadAuditData = function(){
	data(audit)

	data = audit
	data$ID = NULL
	data$IGNORE_Accounts = NULL
	data$RISK_Adjustment = NULL

	names(data) = gsub("TARGET_Adjusted", "Adjusted", names(data))

	data$Deductions = as.logical(data$Deductions > 0)

	data$Adjusted = as.factor(data$Adjusted)

	return (data)
}
