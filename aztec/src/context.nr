use dep::protocol_types::{
    abis::{
        block_header::BlockHeader,
        call_context::CallContext,
        function_data::FunctionData,
        function_selector::FunctionSelector,
        private_circuit_public_inputs::PrivateCircuitPublicInputs,
        public_circuit_public_inputs::PublicCircuitPublicInputs,
        call_stack_item::PrivateCallStackItem,
        call_stack_item::PublicCallStackItem,
    },
    address::{
        AztecAddress,
        EthAddress,
    },
    constants::{
        EMPTY_NULLIFIED_COMMITMENT,
        MAX_NEW_COMMITMENTS_PER_CALL,
        MAX_NEW_L2_TO_L1_MSGS_PER_CALL,
        MAX_NEW_NULLIFIERS_PER_CALL,
        MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL,
        MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL,
        MAX_PUBLIC_DATA_READS_PER_CALL,
        MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL,
        MAX_READ_REQUESTS_PER_CALL,
        MAX_PENDING_READ_REQUESTS_PER_CALL,
        NUM_FIELDS_PER_SHA256,
        RETURN_VALUES_LENGTH,
    },
    contrakt::{
        deployment_data::ContractDeploymentData,
        storage_read::StorageRead,
        storage_update_request::StorageUpdateRequest,
    },
    hash::hash_args,
    point::Point,
};

// TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
// use dep::std::collections::vec::Vec;

use crate::abi::{
    PrivateContextInputs,
    PublicContextInputs,
};

// l1 to l2 messaging
use crate::messaging::process_l1_to_l2_message;

use crate::types::{
    vec::BoundedVec,
};

use crate::utils::arr_copy_slice;

use crate::oracle::{
    arguments,
    call_private_function::call_private_function_internal,
    public_call::call_public_function_internal,
    enqueue_public_function_call::enqueue_public_function_call_internal,
    context::get_portal_address,
    get_block_header::get_block_header,
};

use dep::std::option::Option;

// When finished, one can call .finish() to convert back to the abi
struct PrivateContext {
    // docs:start:private-context
    inputs: PrivateContextInputs,

    args_hash : Field,
    return_values : BoundedVec<Field, RETURN_VALUES_LENGTH>,

    read_requests: BoundedVec<Field, MAX_READ_REQUESTS_PER_CALL>,
    pending_read_requests: BoundedVec<Field, MAX_PENDING_READ_REQUESTS_PER_CALL>,

    new_commitments: BoundedVec<Field, MAX_NEW_COMMITMENTS_PER_CALL>,
    new_nullifiers: BoundedVec<Field, MAX_NEW_NULLIFIERS_PER_CALL>,
    nullified_commitments: BoundedVec<Field, MAX_NEW_NULLIFIERS_PER_CALL>,

    private_call_stack_hashes : BoundedVec<Field, MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL>,
    public_call_stack_hashes : BoundedVec<Field, MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL>,
    new_l2_to_l1_msgs : BoundedVec<Field, MAX_NEW_L2_TO_L1_MSGS_PER_CALL>,
    // docs:end:private-context

    block_header: BlockHeader,

    // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
    // encrypted_logs_preimages: Vec<Field>,
    // unencrypted_logs_preimages: Vec<Field>,
}

impl PrivateContext {
    pub fn new(inputs: PrivateContextInputs, args_hash: Field) -> PrivateContext {
        PrivateContext {
            inputs: inputs,

            args_hash: args_hash,
            return_values: BoundedVec::new(0),

            read_requests: BoundedVec::new(0),
            pending_read_requests: BoundedVec::new(0),

            new_commitments: BoundedVec::new(0),
            new_nullifiers: BoundedVec::new(0),
            nullified_commitments: BoundedVec::new(0),

            block_header: inputs.block_header,

            private_call_stack_hashes: BoundedVec::new(0),
            public_call_stack_hashes: BoundedVec::new(0),
            new_l2_to_l1_msgs: BoundedVec::new(0),

            // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
            // encrypted_logs_preimages: Vec::new(),
            // unencrypted_logs_preimages: Vec::new(),
        }
    }

    pub fn msg_sender(self) -> AztecAddress {
        self.inputs.call_context.msg_sender
    }

    pub fn this_address(self) -> AztecAddress {
        self.inputs.call_context.storage_contract_address
    }

    pub fn this_portal_address(self) -> EthAddress {
        self.inputs.call_context.portal_contract_address
    }

    pub fn chain_id(self) -> Field {
        self.inputs.private_global_variables.chain_id
    }

    pub fn version(self) -> Field {
        self.inputs.private_global_variables.version
    }

    pub fn selector(self) -> FunctionSelector {
        self.inputs.call_context.function_selector
    }

    pub fn get_block_header(self, block_number: u32) -> BlockHeader {
        get_block_header(block_number, self)
    }

    pub fn finish(self) -> PrivateCircuitPublicInputs {
        // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
        let encrypted_logs_hash = [0; NUM_FIELDS_PER_SHA256];
        let unencrypted_logs_hash = [0; NUM_FIELDS_PER_SHA256];
        let encrypted_log_preimages_length = 0;
        let unencrypted_log_preimages_length = 0;

        let priv_circuit_pub_inputs = PrivateCircuitPublicInputs {
            call_context: self.inputs.call_context,
            args_hash: self.args_hash,
            return_values: self.return_values.storage,
            read_requests: self.read_requests.storage,
            pending_read_requests: self.pending_read_requests.storage,
            new_commitments: self.new_commitments.storage,
            new_nullifiers: self.new_nullifiers.storage,
            nullified_commitments: self.nullified_commitments.storage,
            private_call_stack_hashes: self.private_call_stack_hashes.storage,
            public_call_stack_hashes: self.public_call_stack_hashes.storage,
            new_l2_to_l1_msgs: self.new_l2_to_l1_msgs.storage,
            encrypted_logs_hash: encrypted_logs_hash,
            unencrypted_logs_hash: unencrypted_logs_hash,
            encrypted_log_preimages_length: encrypted_log_preimages_length,
            unencrypted_log_preimages_length: unencrypted_log_preimages_length,
            block_header: self.block_header,
            contract_deployment_data: self.inputs.contract_deployment_data,
            chain_id: self.inputs.private_global_variables.chain_id,
            version: self.inputs.private_global_variables.version,
        };
        priv_circuit_pub_inputs
    }

    pub fn push_read_request(&mut self, read_request: Field) {
        self.read_requests.push(read_request);
    }

    pub fn push_pending_read_request(&mut self, pending_read_request: Field) {
        self.pending_read_requests.push(pending_read_request);
    }

    pub fn push_new_note_hash(&mut self, note_hash: Field) {
        self.new_commitments.push(note_hash);
    }

    // We never push a zero nullified_commitment as zero is used to indicate the end
    // of a field array in private kernel. This routine transparently replaces a
    // zero value into the special placeholder: EMPTY_NULLIFIED_COMMITMENT.
    pub fn push_new_nullifier(&mut self, nullifier: Field, nullified_commitment: Field) {
        self.new_nullifiers.push(nullifier);
        let mut non_zero_nullified = nullified_commitment;
        if (non_zero_nullified == 0) {
            non_zero_nullified = EMPTY_NULLIFIED_COMMITMENT;
        }
        self.nullified_commitments.push(non_zero_nullified);
    }

    // docs:start:context_message_portal
    pub fn message_portal(&mut self, content: Field) 
    // docs:end:context_message_portal
    {
        self.new_l2_to_l1_msgs.push(content);
    }

    // PrivateContextInputs must be temporarily passed in to prevent too many unknowns
    // Note this returns self to get around an issue where mutable structs do not maintain mutations unless reassigned
    // docs:start:context_consume_l1_to_l2_message
    // docs:start:consume_l1_to_l2_message
    pub fn consume_l1_to_l2_message(
        &mut self,
        msg_key: Field,
        content: Field,
        secret: Field
    ) 
    // docs:end:context_consume_l1_to_l2_message
    {
        let nullifier = process_l1_to_l2_message(self.block_header.l1_to_l2_messages_tree_root, self.this_address(), self.this_portal_address(), self.chain_id(), self.version(), msg_key, content, secret);

        // Push nullifier (and the "commitment" corresponding to this can be "empty")
        self.push_new_nullifier(nullifier, EMPTY_NULLIFIED_COMMITMENT)
    }
    // docs:end:consume_l1_to_l2_message

    pub fn accumulate_encrypted_logs<N>(&mut self, log: [Field; N]) {
        let _void1 = self.inputs;
        let _void2 = log;
        // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
    }

    pub fn accumulate_unencrypted_logs<T>(&mut self, log: T) {
        let _void1 = self.inputs;
        let _void2 = log;
        // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
    }

    pub fn call_private_function<ARGS_COUNT>(
        &mut self,
        contract_address: AztecAddress, 
        function_selector: FunctionSelector, 
        args: [Field; ARGS_COUNT]
    ) -> [Field; RETURN_VALUES_LENGTH] {
        let args_hash = hash_args(args);
        assert(args_hash == arguments::pack_arguments(args));
        self.call_private_function_with_packed_args(contract_address, function_selector, args_hash)
    }

    pub fn call_private_function_no_args(
        &mut self,
        contract_address: AztecAddress, 
        function_selector: FunctionSelector, 
    ) -> [Field; RETURN_VALUES_LENGTH] {
        self.call_private_function_with_packed_args(contract_address, function_selector, 0)
    }

    pub fn call_private_function_with_packed_args(
        &mut self,
        contract_address: AztecAddress,
        function_selector: FunctionSelector,
        args_hash: Field
    ) -> [Field; RETURN_VALUES_LENGTH] {
        let fields = call_private_function_internal(
            contract_address,
            function_selector, 
            args_hash
        );
        let item = PrivateCallStackItem {
            contract_address: AztecAddress::from_field(fields[0]),
            function_data: FunctionData {
                selector: FunctionSelector::from_field(fields[1]),
                is_internal: fields[2] as bool,
                is_private: fields[3] as bool,
                is_constructor: fields[4] as bool,
            },
            public_inputs: PrivateCircuitPublicInputs {
                call_context: CallContext {
                    msg_sender : AztecAddress::from_field(fields[5]),
                    storage_contract_address : AztecAddress::from_field(fields[6]),
                    portal_contract_address : EthAddress::from_field(fields[7]),
                    function_selector: FunctionSelector::from_field(fields[8]), // practically same as fields[1]
                    is_delegate_call : fields[9] as bool,
                    is_static_call : fields[10] as bool,
                    is_contract_deployment: fields[11] as bool,
                },
                // TODO handle the offsets as a variable incremented during extraction?
                args_hash: fields[12],
                return_values: arr_copy_slice(fields, [0; RETURN_VALUES_LENGTH], 13),
                read_requests: arr_copy_slice(fields, [0; MAX_READ_REQUESTS_PER_CALL], 17),
                pending_read_requests: arr_copy_slice(fields, [0; MAX_READ_REQUESTS_PER_CALL], 49),
                new_commitments: arr_copy_slice(fields, [0; MAX_NEW_COMMITMENTS_PER_CALL], 81),
                new_nullifiers: arr_copy_slice(fields, [0; MAX_NEW_NULLIFIERS_PER_CALL], 97),
                nullified_commitments: arr_copy_slice(fields, [0; MAX_NEW_NULLIFIERS_PER_CALL], 113),
                private_call_stack_hashes: arr_copy_slice(fields, [0; MAX_PRIVATE_CALL_STACK_LENGTH_PER_CALL], 129),
                public_call_stack_hashes: arr_copy_slice(fields, [0; MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL], 133),
                new_l2_to_l1_msgs: arr_copy_slice(fields, [0; MAX_NEW_L2_TO_L1_MSGS_PER_CALL], 137),
                encrypted_logs_hash: arr_copy_slice(fields, [0; NUM_FIELDS_PER_SHA256], 139),
                unencrypted_logs_hash: arr_copy_slice(fields, [0; NUM_FIELDS_PER_SHA256], 141),
                encrypted_log_preimages_length: fields[143],
                unencrypted_log_preimages_length: fields[144],
                block_header: BlockHeader {
                    // Must match order in `private_circuit_public_inputs.hpp`
                    note_hash_tree_root : fields[145],
                    nullifier_tree_root : fields[146],
                    contract_tree_root : fields[147],
                    l1_to_l2_messages_tree_root : fields[148],
                    archive_root : fields[149],
                    public_data_tree_root: fields[150],
                    global_variables_hash: fields[151],
                },
                contract_deployment_data: ContractDeploymentData {
                    deployer_public_key: Point {
                        x: fields[152],
                        y: fields[153],
                    },
                    constructor_vk_hash : fields[154],
                    function_tree_root : fields[155],
                    contract_address_salt : fields[156],
                    portal_contract_address : EthAddress::from_field(fields[157]),
                },
                chain_id: fields[158],
                version: fields[159],
            },
            is_execution_request: fields[160] as bool,
        };
        assert(contract_address.eq(item.contract_address));
        assert(function_selector.eq(item.function_data.selector));

        assert(args_hash == item.public_inputs.args_hash);

        assert(item.is_execution_request == false);

        // Assert that the call context of the enqueued call generated by the oracle matches our request.
        // We are issuing a regular call which is not delegate, static, or deployment. We also constrain
        // the msg_sender in the nested call to be equal to our address, and the execution context address
        // for the nested call to be equal to the address we actually called.
        assert(item.public_inputs.call_context.is_delegate_call == false);
        assert(item.public_inputs.call_context.is_static_call == false);
        assert(item.public_inputs.call_context.is_contract_deployment == false);
        assert(item.public_inputs.call_context.msg_sender.eq(self.inputs.call_context.storage_contract_address));
        assert(item.public_inputs.call_context.storage_contract_address.eq(contract_address));

        self.private_call_stack_hashes.push(item.hash());

        item.public_inputs.return_values
    }

    pub fn call_public_function<ARGS_COUNT>(
        &mut self,
        contract_address: AztecAddress, 
        function_selector: FunctionSelector, 
        args: [Field; ARGS_COUNT]
    ) {
        let args_hash = hash_args(args);
        assert(args_hash == arguments::pack_arguments(args));
        self.call_public_function_with_packed_args(contract_address, function_selector, args_hash)
    }

    pub fn call_public_function_no_args(
        &mut self,
        contract_address: AztecAddress, 
        function_selector: FunctionSelector,
    ) {
        self.call_public_function_with_packed_args(contract_address, function_selector, 0)
    }

    pub fn call_public_function_with_packed_args(
        &mut self,
        contract_address: AztecAddress,
        function_selector: FunctionSelector,
        args_hash: Field
    ) {
        let fields = enqueue_public_function_call_internal(
            contract_address, 
            function_selector, 
            args_hash
        );
        let item = PublicCallStackItem {
            contract_address:  AztecAddress::from_field(fields[0]),
            function_data: FunctionData {
                selector: FunctionSelector::from_field(fields[1]),
                is_internal: fields[2] as bool,
                is_private: fields[3] as bool,
                is_constructor: fields[4] as bool,
            },
            public_inputs: PublicCircuitPublicInputs {
                call_context: CallContext {
                    msg_sender : AztecAddress::from_field(fields[5]),
                    storage_contract_address : AztecAddress::from_field(fields[6]),
                    portal_contract_address : EthAddress::from_field(fields[7]),
                    function_selector: FunctionSelector::from_field(fields[8]), // practically same as fields[1]
                    is_delegate_call : fields[9] as bool,
                    is_static_call : fields[10] as bool,
                    is_contract_deployment: fields[11] as bool,
                },
                args_hash: fields[12],
                return_values: [0; RETURN_VALUES_LENGTH],
                contract_storage_update_requests: [StorageUpdateRequest::empty(); MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL],
                contract_storage_reads: [StorageRead::empty(); MAX_PUBLIC_DATA_READS_PER_CALL],
                public_call_stack_hashes: [0; MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL],
                new_commitments: [0; MAX_NEW_COMMITMENTS_PER_CALL],
                new_nullifiers: [0; MAX_NEW_NULLIFIERS_PER_CALL],
                new_l2_to_l1_msgs:[0; MAX_NEW_L2_TO_L1_MSGS_PER_CALL],
                unencrypted_logs_hash:[0; NUM_FIELDS_PER_SHA256],
                unencrypted_log_preimages_length: 0,
                block_header: BlockHeader::empty(),
                prover_address: AztecAddress::zero(),
            },
            is_execution_request: true,
        };

        assert(contract_address.eq(item.contract_address));
        assert(function_selector.eq(item.function_data.selector));
        
        assert(args_hash == item.public_inputs.args_hash);

        // Assert that the call context of the enqueued call generated by the oracle matches our request.
        // We are issuing a regular call which is not delegate, static, or deployment. We also constrain
        // the msg_sender in the nested call to be equal to our address, and the execution context address
        // for the nested call to be equal to the address we actually called.
        assert(item.public_inputs.call_context.is_delegate_call == false);
        assert(item.public_inputs.call_context.is_static_call == false);
        assert(item.public_inputs.call_context.is_contract_deployment == false);
        assert(item.public_inputs.call_context.msg_sender.eq(self.inputs.call_context.storage_contract_address));
        assert(item.public_inputs.call_context.storage_contract_address.eq(contract_address));

        self.public_call_stack_hashes.push(item.hash());
    }
}

struct PublicContext {
    inputs: PublicContextInputs,

    args_hash : Field,
    return_values : BoundedVec<Field, RETURN_VALUES_LENGTH>,

    contract_storage_update_requests: BoundedVec<StorageUpdateRequest, MAX_PUBLIC_DATA_UPDATE_REQUESTS_PER_CALL>,
    contract_storage_reads: BoundedVec<StorageRead, MAX_PUBLIC_DATA_READS_PER_CALL>,
    public_call_stack_hashes: BoundedVec<Field, MAX_PUBLIC_CALL_STACK_LENGTH_PER_CALL>,

    new_commitments: BoundedVec<Field, MAX_NEW_COMMITMENTS_PER_CALL>,
    new_nullifiers: BoundedVec<Field, MAX_NEW_NULLIFIERS_PER_CALL>,

    new_l2_to_l1_msgs: BoundedVec<Field, MAX_NEW_L2_TO_L1_MSGS_PER_CALL>,

    unencrypted_logs_hash: BoundedVec<Field, NUM_FIELDS_PER_SHA256>,
    unencrypted_logs_preimages_length: Field,

    block_header: BlockHeader,
    prover_address: AztecAddress,
}

impl PublicContext {
    pub fn new(inputs: PublicContextInputs, args_hash: Field) -> PublicContext {
        let empty_storage_read = StorageRead::empty();
        let empty_storage_update = StorageUpdateRequest::empty();
        PublicContext {
            inputs: inputs,

            args_hash: args_hash,
            return_values: BoundedVec::new(0),

            contract_storage_update_requests: BoundedVec::new(empty_storage_update),
            contract_storage_reads: BoundedVec::new(empty_storage_read),
            public_call_stack_hashes: BoundedVec::new(0),

            new_commitments: BoundedVec::new(0),
            new_nullifiers: BoundedVec::new(0),

            new_l2_to_l1_msgs: BoundedVec::new(0),

            
            unencrypted_logs_hash: BoundedVec::new(0),
            unencrypted_logs_preimages_length: 0,

            block_header: inputs.block_header,
            prover_address: AztecAddress::zero(),

            // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
            // encrypted_logs_preimages: Vec::new(),
            // unencrypted_logs_preimages: Vec::new(),
        }
    }

    pub fn msg_sender(self) -> AztecAddress {
        self.inputs.call_context.msg_sender
    }

    pub fn this_address(self) -> AztecAddress {
        self.inputs.call_context.storage_contract_address
    }

    pub fn this_portal_address(self) -> EthAddress {
        self.inputs.call_context.portal_contract_address
    }

    pub fn chain_id(self) -> Field {
        self.inputs.public_global_variables.chain_id
    }

    pub fn version(self) -> Field {
        self.inputs.public_global_variables.version
    }

    pub fn selector(self) -> FunctionSelector {
        self.inputs.call_context.function_selector
    }

    pub fn block_number(self) -> Field {
        self.inputs.public_global_variables.block_number
    }

    pub fn timestamp(self) -> Field {
        self.inputs.public_global_variables.timestamp
    }

    pub fn finish(self) -> PublicCircuitPublicInputs {
        // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
        let unencrypted_logs_hash = [0; NUM_FIELDS_PER_SHA256];
        let unencrypted_log_preimages_length = 0;


        // Compute the public call stack hashes
        let pub_circuit_pub_inputs = PublicCircuitPublicInputs {
            call_context: self.inputs.call_context, // Done
            args_hash: self.args_hash, // Done
            contract_storage_update_requests: self.contract_storage_update_requests.storage,
            contract_storage_reads: self.contract_storage_reads.storage,
            return_values: self.return_values.storage,
            new_commitments: self.new_commitments.storage,
            new_nullifiers: self.new_nullifiers.storage,
            public_call_stack_hashes: self.public_call_stack_hashes.storage,
            new_l2_to_l1_msgs: self.new_l2_to_l1_msgs.storage,
            unencrypted_logs_hash: unencrypted_logs_hash,
            unencrypted_log_preimages_length: unencrypted_log_preimages_length,
            block_header: self.inputs.block_header,
            prover_address: self.prover_address,
        };
        pub_circuit_pub_inputs
    }

    pub fn push_new_note_hash(&mut self, note_hash: Field) {
        self.new_commitments.push(note_hash);
    }

    pub fn push_new_nullifier(&mut self, nullifier: Field, _nullified_commitment: Field) {
        self.new_nullifiers.push(nullifier);
    }

    pub fn message_portal(&mut self, content: Field) {
        self.new_l2_to_l1_msgs.push(content);
    }

    // PrivateContextInputs must be temporarily passed in to prevent too many unknowns
    // Note this returns self to get around an issue where mutable structs do not maintain mutations unless reassigned
    pub fn consume_l1_to_l2_message(&mut self, msg_key: Field, content: Field, secret: Field) {
        let this = (*self).this_address();
        let nullifier = process_l1_to_l2_message(self.block_header.l1_to_l2_messages_tree_root, this, self.this_portal_address(), self.chain_id(), self.version(), msg_key, content, secret);

        // Push nullifier (and the "commitment" corresponding to this can be "empty")
        self.push_new_nullifier(nullifier, EMPTY_NULLIFIED_COMMITMENT)
    }

    pub fn accumulate_encrypted_logs<N>(&mut self, log: [Field; N]) {
        let _void1 = self;
        let _void2 = log;
        // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
    }

    pub fn accumulate_unencrypted_logs<T>(&mut self, log: T) {
        let _void1 = self;
        let _void2 = log;
        // TODO(https://github.com/AztecProtocol/aztec-packages/issues/1165)
    }

    pub fn call_public_function<ARGS_COUNT>(
        _self: Self,
        contract_address: AztecAddress, 
        function_selector: FunctionSelector,
        args: [Field; ARGS_COUNT],
    ) -> [Field; RETURN_VALUES_LENGTH] {
        let args_hash = hash_args(args);
        assert(args_hash == arguments::pack_arguments(args));
        call_public_function_internal(
            contract_address, 
            function_selector, 
            args_hash,
        )
    }

    pub fn call_public_function_no_args(
        _self: Self,
        contract_address: AztecAddress, 
        function_selector: FunctionSelector,
    ) -> [Field; RETURN_VALUES_LENGTH] {
        call_public_function_internal(
            contract_address, 
            function_selector, 
            0,
        )
    }

}

struct Context {
    private: Option<&mut PrivateContext>,
    public: Option<&mut PublicContext>,
}

impl Context {
    pub fn private(context: &mut PrivateContext) -> Context {
        Context {
            private: Option::some(context),
            public: Option::none()
        }
    }

    pub fn public(context: &mut PublicContext) -> Context {
        Context {
            public: Option::some(context),
            private: Option::none()
        }
    }

    pub fn none() -> Context {
        Context {
            public: Option::none(),
            private: Option::none()
        }
    }
}
