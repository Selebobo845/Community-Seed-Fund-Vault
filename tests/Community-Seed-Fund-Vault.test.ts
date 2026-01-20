
import { describe, expect, it } from "vitest";
import { Cl, ClarityType } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const deployer = accounts.get("deployer")!;

const contractName = "Community-Seed-Fund-Vault";

/*
  The test below is an example. To learn more, read the testing documentation here:
  https://docs.hiro.so/stacks/clarinet-js-sdk
*/

describe("example tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });
});

describe("Loan Alert System Tests", () => {
  
  it("should initialize default alert settings", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-alert-settings",
      [],
      address1
    );
    
    expect(result).toHaveClarityType(ClarityType.Tuple);
    const settings = result.data;
    expect(settings['seven-day-threshold']).toBeUint(1008);
    expect(settings['three-day-threshold']).toBeUint(432);
    expect(settings['one-day-threshold']).toBeUint(144);
    expect(settings['enabled']).toBeBool(true);
  });
  
  it("should update alert thresholds (owner only)", () => {
    // Owner should be able to update thresholds
    const { result: updateResult } = simnet.callPublicFn(
      contractName,
      "update-alert-thresholds",
      [Cl.uint(2016), Cl.uint(864), Cl.uint(288), Cl.uint(200000000)], // 14d, 6d, 2d, 2000 STX
      deployer
    );
    
    expect(updateResult).toHaveClarityType(ClarityType.ResponseOk);
    expect(updateResult.value).toBeBool(true);
    
    // Verify settings were updated
    const { result: settingsResult } = simnet.callReadOnlyFn(
      contractName,
      "get-alert-settings",
      [],
      address1
    );
    
    expect(settingsResult).toHaveClarityType(ClarityType.Tuple);
    const updatedSettings = settingsResult.data;
    expect(updatedSettings['seven-day-threshold']).toBeUint(2016);
    expect(updatedSettings['three-day-threshold']).toBeUint(864);
    expect(updatedSettings['one-day-threshold']).toBeUint(288);
    expect(updatedSettings['fund-low-balance-threshold']).toBeUint(200000000);
  });
  
  it("should reject invalid alert threshold updates", () => {
    // Non-owner should be rejected
    const { result: nonOwnerResult } = simnet.callPublicFn(
      contractName,
      "update-alert-thresholds",
      [Cl.uint(1000), Cl.uint(500), Cl.uint(100), Cl.uint(1000000)],
      address1
    );
    
    expect(nonOwnerResult).toBeErr(Cl.uint(100)); // ERR_UNAUTHORIZED
    
    // Invalid thresholds (not descending) should be rejected
    const { result: invalidResult } = simnet.callPublicFn(
      contractName,
      "update-alert-thresholds",
      [Cl.uint(100), Cl.uint(200), Cl.uint(300), Cl.uint(1000000)], // Invalid: ascending instead of descending
      deployer
    );
    
    expect(invalidResult).toBeErr(Cl.uint(115)); // ERR_INVALID_ALERT_THRESHOLD
  });
  
  it("should calculate fund health score correctly", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "calculate-fund-health-score",
      [],
      address1
    );
    
    expect(result).toHaveClarityType(ClarityType.Tuple);
    const healthScore = result.data;
    
    // Should have structure with all required fields
    expect(healthScore).toHaveProperty('overall-score');
    expect(healthScore).toHaveProperty('balance-score');
    expect(healthScore).toHaveProperty('activity-score');
    expect(healthScore).toHaveProperty('stability-score');
    expect(healthScore).toHaveProperty('fund-balance');
    expect(healthScore).toHaveProperty('total-loans');
    expect(healthScore).toHaveProperty('last-calculated');
    
    // Initial state should have specific scores
    expect(healthScore['balance-score']).toBeUint(0);  // No funds initially
    expect(healthScore['activity-score']).toBeUint(0);  // No loans initially
    expect(healthScore['stability-score']).toBeUint(30); // Default stability
    expect(healthScore['overall-score']).toBeUint(30);   // Sum of components
  });
  
  it("should trigger fund low balance alert correctly", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "trigger-fund-low-balance-alert",
      [],
      address1
    );
    
    expect(result).toHaveClarityType(ClarityType.Tuple);
    const alertData = result.data;
    
    expect(alertData).toHaveProperty('alert-triggered');
    expect(alertData).toHaveProperty('current-balance');
    expect(alertData).toHaveProperty('threshold');
    expect(alertData).toHaveProperty('deficit');
    expect(alertData).toHaveProperty('percentage-of-threshold');
    
    // With zero balance, alert should be triggered
    expect(alertData['alert-triggered']).toBeBool(true);
    expect(alertData['current-balance']).toBeUint(0);
  });
  
  it("should check loan due dates for non-existent loan", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "check-loan-due-dates",
      [Cl.uint(999)], // Non-existent loan ID
      address1
    );
    
    expect(result).toBeNone();
  });
  
  it("should generate loan status report for non-existent loan", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "generate-loan-status-report",
      [Cl.uint(999)], // Non-existent loan ID
      address1
    );
    
    expect(result).toBeNone();
  });
  
  it("should get overdue loan summary with initial state", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-overdue-loan-summary",
      [],
      address1
    );
    
    expect(result).toHaveClarityType(ClarityType.Tuple);
    const summary = result.data;
    
    expect(summary).toHaveProperty('total-loans');
    expect(summary).toHaveProperty('overdue-count');
    expect(summary).toHaveProperty('total-overdue-amount');
    expect(summary).toHaveProperty('average-days-overdue');
    expect(summary).toHaveProperty('last-updated');
    
    // Initial state should have no loans
    expect(summary['total-loans']).toBeUint(0);
    expect(summary['overdue-count']).toBeUint(0);
    expect(summary['total-overdue-amount']).toBeUint(0);
  });
  
  it("should get loan risk assessment for non-existent loan", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-loan-risk-assessment",
      [Cl.uint(999)], // Non-existent loan ID
      address1
    );
    
    expect(result).toBeNone();
  });
  
  it("should get fund health metrics with initial state", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-fund-health-metrics",
      [],
      address1
    );
    
    expect(result).toHaveClarityType(ClarityType.Tuple);
    const metrics = result.data;
    
    expect(metrics).toHaveProperty('total-active-loans');
    expect(metrics).toHaveProperty('total-overdue-loans');
    expect(metrics).toHaveProperty('utilization-rate');
    expect(metrics).toHaveProperty('default-rate');
    expect(metrics).toHaveProperty('last-updated');
    
    // Initial state should have all zeros
    expect(metrics['total-active-loans']).toBeUint(0);
    expect(metrics['total-overdue-loans']).toBeUint(0);
    expect(metrics['utilization-rate']).toBeUint(0);
    expect(metrics['default-rate']).toBeUint(0);
  });
  
  it("should get loan alert status for non-existent loan", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-loan-alert-status",
      [Cl.uint(999)], // Non-existent loan ID
      address1
    );
    
    expect(result).toBeNone();
  });
});

describe("Integrated Alert System Tests", () => {
  
  it("should test full loan workflow with alert tracking", () => {
    // 1. Register farmer
    const { result: registerResult } = simnet.callPublicFn(
      contractName,
      "register-farmer",
      [Cl.stringAscii("Test Farmer"), Cl.stringAscii("Test Location")],
      address1
    );
    expect(registerResult).toHaveClarityType(ClarityType.ResponseOk);
    
    // 2. Add funds to vault
    const { result: contributeResult } = simnet.callPublicFn(
      contractName,
      "contribute-to-fund",
      [Cl.uint(1000000000)], // 10,000 STX
      address2
    );
    expect(contributeResult).toHaveClarityType(ClarityType.ResponseOk);
    
    // 3. Request loan (should initialize alert tracking)
    const { result: loanResult } = simnet.callPublicFn(
      contractName,
      "request-loan",
      [Cl.uint(500000000)], // 5,000 STX
      address1
    );
    expect(loanResult).toHaveClarityType(ClarityType.ResponseOk);
    const loanId = Number((loanResult.value as any).value);
    
    // 4. Check that loan alerts were initialized
    const { result: alertStatus } = simnet.callReadOnlyFn(
      contractName,
      "get-loan-alert-status",
      [Cl.uint(loanId)],
      address1
    );
    
    expect(alertStatus).toHaveClarityType(ClarityType.OptionalSome);
    const alertData = (alertStatus as any).value.data;
    expect(alertData['seven-day-alert']).toBeBool(false);
    expect(alertData['three-day-alert']).toBeBool(false);
    expect(alertData['one-day-alert']).toBeBool(false);
    expect(alertData['overdue-alert']).toBeBool(false);
    
    // 5. Approve loan to get due date
    const { result: approveResult } = simnet.callPublicFn(
      contractName,
      "approve-loan",
      [Cl.uint(loanId)],
      deployer
    );
    expect(approveResult).toHaveClarityType(ClarityType.ResponseOk);
    
    // 6. Check loan due dates
    const { result: dueDateCheck } = simnet.callReadOnlyFn(
      contractName,
      "check-loan-due-dates",
      [Cl.uint(loanId)],
      address1
    );
    
    expect(dueDateCheck).toHaveClarityType(ClarityType.OptionalSome);
    const dueDateInfo = (dueDateCheck as any).value.data;
    expect(dueDateInfo['loan-id']).toBeUint(loanId);
    expect(dueDateInfo).toHaveProperty('due-block');
    expect(dueDateInfo).toHaveProperty('blocks-remaining');
    
    // 7. Generate comprehensive loan status report
    const { result: statusReport } = simnet.callReadOnlyFn(
      contractName,
      "generate-loan-status-report",
      [Cl.uint(loanId)],
      address1
    );
    
    expect(statusReport).toHaveClarityType(ClarityType.OptionalSome);
    const report = (statusReport as any).value.data;
    expect(report['loan-id']).toBeUint(loanId);
    expect(report['farmer']).toBePrincipal(address1);
    expect(report['amount']).toBeUint(500000000);
    expect(report['approved']).toBeBool(true);
    expect(report['repaid']).toBeBool(false);
    
    // 8. Get loan risk assessment
    const { result: riskAssessment } = simnet.callReadOnlyFn(
      contractName,
      "get-loan-risk-assessment",
      [Cl.uint(loanId)],
      address1
    );
    
    expect(riskAssessment).toHaveClarityType(ClarityType.OptionalSome);
    const risk = (riskAssessment as any).value.data;
    expect(risk['loan-id']).toBeUint(loanId);
    expect(risk['farmer']).toBePrincipal(address1);
    expect(risk).toHaveProperty('reputation-score');
    expect(risk).toHaveProperty('total-risk-score');
    expect(risk).toHaveProperty('risk-level');
    
    // 9. Check fund health after loan approval
    const { result: healthAfterLoan } = simnet.callReadOnlyFn(
      contractName,
      "calculate-fund-health-score",
      [],
      address1
    );
    
    const health = healthAfterLoan.data;
    expect(health['fund-balance']).toBeUint(500000000);
    expect(health['total-loans']).toBeUint(1);
    expect(health['activity-score']).toBeUint(30); // Should have activity now
    
    // 10. Check that fund low balance alert is not triggered with sufficient funds
    const { result: balanceAlert } = simnet.callReadOnlyFn(
      contractName,
      "trigger-fund-low-balance-alert",
      [],
      address1
    );
    
    const alertInfo = balanceAlert.data;
    expect(alertInfo['alert-triggered']).toBeBool(false);
    expect(alertInfo['current-balance']).toBeUint(500000000);
  });
});
