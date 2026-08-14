extends GutTest

# Tests for: TransitionProposal (scripts/base/transition_proposal.gd)

func after_each():
	assert_no_new_orphans()

func test_init_assigns_values():
	var subject = TransitionProposal.new(1, TransitionProposal.Priority.PLAYER_REQUESTED, 10, &"test_source")
	
	assert_eq(subject.target_state, 1)
	assert_eq(subject.category, TransitionProposal.Priority.PLAYER_REQUESTED)
	assert_eq(subject.override_weight, 10)
	assert_eq(subject.source_id, &"test_source")

func test_init_defaults():
	var subject = TransitionProposal.new(5)
	
	assert_eq(subject.target_state, 5)
	assert_eq(subject.category, TransitionProposal.Priority.DEFAULT)
	assert_eq(subject.override_weight, 0)
	assert_eq(subject.source_id, &"")
