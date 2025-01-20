// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

AcrossSettlementContract is ISettlementContract {

	// Unique Across nonce
	uint256 depositId;
	// Permit2 contract for this network
	address constant PERMIT2;

	// Data unique to every CrossChainOrder settled on Across
	struct AcrossOrderData {
		uint32 exclusivityDeadline;
		address exclusiveRelayer;
		bytes message;
	}

	// Data unique to every attempted order fulfillment
	struct AcrossFillerData {
		// Filler can choose where they want to be repaid
	  uint256 repaymentChainId;
	}

	function initiate(CrossChainOrder order, bytes signature, bytes fillerData) external {  
	  // Ensure that order was intended to be settled by Across.
	  require(order.settlementContract == address(this));
	  require(order.originChainId == block.chainId);
  
	  // Extract Across-specific params.
	  (resolvedOrder, acrossOrderData) = _resolve(order, fillerData);

		 // Verify Permit2 signature and pull user funds into this contract
		_processPermit2Order(PERMIT2, order, resolvedOrder, signature);
	
		// Emit Across-specific event used for settlement.
		emit FundsDepositedV3(
			resolvedOrder.swapperInputs[0].token,
			resolvedOrder.outputs[0].token,
			resolvedOrder.swapperInputs[0].amount,
			resolvedOrder.outputs[0].amount,
			resolvedOrder.outputs[0].chainId,
			depositId++, // Unique Across nonce
			block.timestamp,
			order.fillDeadline,
			acrossOrderData.exclusivityDeadline,
			order.swapper
			resolvedOrder.outputs[0].recipient,
			acrossOrderData.exclusiveRelayer,
			acrossOrderData.message
		);
	}

	function resolve(CrossChainOrder order, bytes fillerData) external view returns (ResolvedCrossChainOrder) {    
	  (resolvedOrder, ) = _resolve(order, fillerData);
	}

	// Filler calls this function on the destinationChainId to fulfill an order.
	// This function would not always be defined in this SettlementContract, but
	// for illustrative purposes it is included here.
	// (In most cases, the full `order` and `fillerData` wouldn't need to be supplied
	// here, instead a subset would suffice).
	function fillCrossChainOrder(CrossChainOrder order, bytes fillerData) external {
		// Ensure order has not expired
		require(order.fillDeadline >= block.timestamp)
	
	  (, acrossOrderData, acrossFillerData) = _resolve(order, fillerData);
	  
	  // Pull tokens from filler to fill recipient
	  IERC20(resolvedOrder.outputs[0].token).transferFrom(
		  msg.sender, 
		  address(this), 
		  resolvedOrder.outputs[0].amount
		);
		IERC20(crossChainOrder.outputs[0].token).transfer(
		  resolvedOrder.outputs[0].recipient, 
		  resolvedOrder.outputs[0].amount
		);
  
	  // Signal to settlement contract that the cross chain order has been fulfilled
	  // using a combination of standardized order data and Across-specific data decoded
	  // from the standardized order data.
	  emit FilledRelayV3(
	    crossChainOrder.swapperInputs[0].token,
      crossChainOrder.swapperOutputs[0].token,
      crossChainOrder.swapperInputs[0].amount,
      crossChainOrder.outputs[0].amount,
      acrossFillerData.repaymentChainId,
      order.originChainId,
      acrossOrderData.depositId,
      order.fillDeadline,
      acrossOrderData.exclusivityDeadline,
      acrossOrderData.exclusiveRelayer,
      msg.sender,
      order.swapper,
      acrossOrderData.recipient,
      acrossOrderData.message
	  );
     }

    function _resolve(CrossChainOrder order, bytes fillerData) internal 
	returns(
		AcrossOrderData acrossOrderData, 
		ResolvedCrossChainOrder resolvedCrossChainOrder,
		AcrossFillerData acrossFillerData
	) {
	// Extract Across-specific params.
	acrossOrderData = abi.decode(order.orderData, (AcrossOrderData));
	
	// Compute filler fee using filler-provided data.
	acrossFillerData = abi.decode(fillerData, (AcrossFillerData));
	Output memory fee = FeeCalculator.computeFee(
			order.originChainId, 
			acrossFillerData.repaymentChainId,
			acrossOrderData.inputToken,
			acrossOrderData.inputAmount
	);
		
	resolvedCrossChainOrder = ResolvedCrossChainOrder ({
			settlementContract: address(this);
			swapper: order.swapper;
			nonce: order.nonce;
			originChainId: order.originChainId;
			initiateDeadline: order.initiateDeadline;
			fillDeadline: order.fillDeadline;
			swapperInputs: [Input({ 
				token: acrossOrderData.inputToken,
				amount: acrossOrderData.inputAmount,
				maximumAmount: acrossOrderData.inputAmount
			})],
			swapperOutputs: [Output({ 
				token: acrossOrderData.outputToken,
				amount: acrossOrderData.outputAmount,
				recipient: acrossOrderData.recipient,
				chainId: acrossOrderData.destinationChainId
			})],
			fillerOutputs: [Output({ 
				token: fee.token,
				amount: acrossOrderData.inputAmount - fee.amount,
				recipient: acrossOrderData.recipient,
				chainId: fee.chainId
			})]
    }

    function _processPermit2Order(
	IPermit2 permit2,
	CrossChainOrder order, 
	ResolvedCrossChain resolvedOrder, 
	bytes signature
    ) internal {
	  IPermit2.PermitTransferFrom memory permit = IPermit2.PermitTransferFrom({
	    permitted: IPermit2.TokenPermissions({ token: resolvedOrder.swapperInputs[0].token, amount: resolvedOrder.swapperInputs[0].maxAmount }),
      nonce: order.nonce,
      deadline: order.initiateDeadline
    });

    IPermit2.SignatureTransferDetails memory signatureTransferDetails = IPermit2.SignatureTransferDetails({
      to: address(this),
      requestedAmount: resolvedOrder.inputs[0].amount
    });

    // Pull user funds.
    permit2.permitWitnessTransferFrom(
      permit,
      signatureTransferDetails,
      order.swapper,
      _hash(order), // witness data hash
      PERMIT2_ORDER_TYPE, // witness data type string
      signature
    );
    }
}