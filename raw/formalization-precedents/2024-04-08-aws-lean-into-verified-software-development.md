# Lean Into Verified Software Development

> Source: https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development/
> Collected: 2026-11-10
> Published: 2024-04-08


Lean Into Verified Software Development
Some software components are really important to get right, like your application’s access control policies and core business logic. There are a growing number of tools to help you verify the correctness of these components by leveraging automated reasoning. In developing Cedar, an open source authorization policy language, we have found that the Lean proof assistant is a great tool for verifying Cedar’s correctness and security properties.
Over the past 6 months, we built a formal model of Cedar in Lean, and proved that Cedar’s components satisfy key safety and security properties. Lean is a full-featured programming language —writing models and proofs is just like writing code, but Lean checks your work to make sure your proofs are correct. Lean is also extremely fast, allowing us to efficiently test our production code (written in Rust) against the Lean models.
Until now, Lean has been used mostly by mathematicians to formalize complex math proofs. But our experience shows it’s also an excellent tool for proofs about software correctness and security. In this post, we’ll describe how we used Lean for Cedar, highlight some potential bumps in the road, and point to resources where you can learn more. We hope sharing our experience can guide your next high-assurance software project!
A brief introduction to Cedar
Cedar is an open source language for writing authorization policies, which developers can use to define and enforce permissions for their applications. To understand how, imagine you’re developing a cloud application for hosting documents in folders. You can use Cedar policies to restrict which users (“principals”) are allowed to view and edit (perform “actions” on) which documents and folders (“resources”). When a user tries to access a document or folder, your application calls the Cedar authorizer to check if the access is allowed by the policies. Your Cedar policies are separate from your application code, enabling you to update one without impacting the other.
Here is an example Cedar policy that lets users perform any action on documents they own:
// The owner of a document can perform any action.
permit (
principal, 
action, 
resource is Document) 
when { 
resource.owner == principal 
};
This policy allows access depending on the resource’s owner. The expression resource is Document checks that the resource is of type Document, which always has the owner attribute.
In addition to permit policies, which grant permissions, Cedar also supports forbid policies, which remove permissions. For example, say that deleted documents are moved to a special “Trash” folder, and you want to ensure that users can’t edit deleted documents. You can do so with the following policy:
// Users can't edit documents in the Trash folder.
forbid (
principal, 
action == Action::"editDoc", 
resource in Folder::"Trash");
Here, resource in Folder::"Trash" means that the resource is contained in the “Trash” folder, either directly or in a deleted subfolder. This policy prevents everyone, including document owners, from editing deleted documents. That’s because forbids override permits: If a request satisfies both a permit policy (because the principal owns the document) and a forbid policy (because the document is deleted), the forbid always wins.
The Cedar SDK consists of three core components: the evaluator, the authorizer, and the validator. The evaluator determines the value of expressions like resource.owner == principal, and the authorizer applies the evaluator to your policies to decide whether a request should be allowed. The validator rules out certain classes of evaluation errors by typechecking policies when you create them. For example, in the first policy above, the validator knows that the access resource.owner will never result in an error because resource is guaranteed to be of type Document.
How Cedar uses Lean for verification-guided development
To assure developers that Cedar is correct and secure, we build it using a process called verification-guided development. This process has two parts. First, we create an executable formal model of each core component in Lean. The model is a highly readable prototype, and with it we prove key correctness properties using Lean’s proof assistant. You construct proofs in Lean by applying tactics — procedures that transform one state of the proof (known facts) into another (implied facts). Lean checks each step, preventing mistakes.
Second, we implement Cedar’s production code in Rust, optimizing for performance and usability. We confirm that the code matches the model by using differential random testing. This involves generating millions of random inputs and checking that both model and code produce the same output on every input. A new version of Cedar isn’t released unless its model, proofs, and differential tests are up to date.
We adopted Lean to write our model because of its fast runtime, extensive libraries, and small trusted computing base (TCB). The fast runtime enables efficient differential testing of Cedar models. The libraries provide reusable verified data structures and tactics built by the open source community. Lean’s small TCB also lets us leverage these contributions without having to trust that they are correct — Lean checks that they are, and we only need to trust Lean’s minimal proof-checking kernel.
A quick tour of modeling and verifying Cedar with Lean
We model Cedar components as Lean functions. For example, here is the authorizer:
def isAuthorized 
(req : Request) 
(entities : Entities) 
(policies : Policies) : Response 
:=
let forbids := satisfiedPolicies .forbid policies req entities
let permits := satisfiedPolicies .permit policies req entities
if forbids.isEmpty && !permits.isEmpty
then { decision := .allow, policies := permits }
else { decision := .deny,  policies := forbids }
The authorizer first computes the set of all satisfied forbid and permit policies. It returns allow only if there are no satisfied forbids and there is at least one satisfied permit.
The authorizer code denies access if a forbid policy is satisfied. Proving this property in Lean requires stating it as a theorem and providing a formal proof:
theorem forbid_trumps_permit 
(request : Request) (entities : Entities) (policies : Policies) :
(∃ (policy : Policy),
policy ∈ policies ∧
policy.effect = forbid ∧
satisfied policy request entities) →
(isAuthorized request entities policies).decision = deny
:= by
intro h
unfold isAuthorized
simp [if_satisfied_then_satisfiedPolicies_non_empty 
forbid policies request entities h]
The theorem (the part prior to the :=) says the following: if a collection of policies contains a forbid that is satisfied by a given request and entities, then calling isAuthorized on these inputs always returns deny.
Proof of this theorem (the part after the :=) is a series of steps showing the conclusion follows from the premises. Here, the premise is a satisfied forbid policy, and the conclusion is the authorizer denying access. The proof applies tactics to transform the premise into the conclusion. The intro tactic adds the premise to the proof state; unfold inlines the authorizer definition; and simp uses an auxiliary theorem to complete the proof.
Lean helps you develop proofs interactively. The IDE shows you the proof state at each tactic application, and Lean checks that you’re applying the tactics correctly. But you need to figure out which tactics to apply at each step to reach the goal. Writing Lean proofs is similar to how programming: tools give you insight into the program state, and you write the steps to transform the inputs into the desired outputs.
Once you learn common tactics, Lean proofs are quick to develop, extend, and maintain. The following table compares our modeling and proof effort in Lean to our implementation effort in Rust, measured in lines of code (LOC):
Component
Lean model (LOC)
Lean proofs (LOC)
Rust production code (LOC)
Custom sets and maps
244
681
N/A
Evaluator and Authorizer
897
347
13664
Validator
532
4686
11251
Total
1673
5714
24915
Our most complex proof establishes the soundness of Cedar’s validator — if the validator accepts a policy, evaluating the policy won’t result in a type error. At 4,686 lines of code, this proof took 18 person-days to develop. Other proofs were much smaller and even faster to write.
Thanks to Lean’s libraries and features like type classes, our models are highly readable and concise. For example, the validator model is 10X smaller than its corresponding Rust implementation, which includes many test cases and extra code to provide useful diagnostic output. This makes the Lean models useful not only for proofs but also as a form of documentation. They provide a compact yet precise specification of Cedar for both Cedar users and developers.
One challenge of using Lean is its strict termination checking. Lean requires all recursive definitions to be well-founded — basically, to bottom out. This requirement can complicate modeling of complex recursive structures. For example, Rust lets us represent Cedar values as a recursive datatype over built-in sets and maps. Lean prohibits this for the standard set and map data types because their invariants introduce circular (not well-founded) reasoning. We worked around this by developing custom set and map data types that replace embedded invariants with separate theorems. Working with the termination checker takes some getting used to, but it eventually becomes second nature, and the payoff is that you know your code is free of infinite loops.
Lean models are fast to execute and proofs are fast to check. On average, Lean takes 5 microseconds to evaluate a differential testing input, compared to 7 microseconds for Rust. These fast execution times allow us to run millions of test cases nightly to compare the model against the production code. Lean checks individual proofs interactively as you’re working on them, providing instantaneous feedback. It takes 185 seconds in total to check all proofs and compile models for execution. This is pretty fast! As a point of comparison, Rust takes 45 seconds to compile and test the implementation code.
Takeaways
We’ve found Lean to be a great tool for verified software development. You get a full-featured programming language, fast proof checker and runtime, and a familiar way to build both models and proofs — by writing programs. If you try it, keep these tips in mind:
Lean into the curve. Proof assistants like Lean have a steep learning curve. You need to learn which tactics to use, and when and how to use them. With practice, proof development becomes an efficient engineering activity, like programming. Proofs are programs in Lean, after all.
Start simple. Tactics and syntax are also programmable. You can write your own tactics, define custom syntax, and embed whole languages in Lean. Start simple: Customize Lean’s simp tactic with auxiliary theorems tailored to your proofs, and define your own notation for key operators. Simple code and proofs are easier to build and maintain.
Stay flexible. Lean may not let you write code as you would in other languages. For example, you may need to adjust how you define a data structure or recursive function to satisfy the termination checker. There are still some small challenges with Lean, such as its sparse documentation and sluggish termination checking for mutual induction. But the community is constantly improving it, and you can always find a way forward.
Learn more
This post explored how we use Lean for verification-guided development of Cedar. Lean’s language enables concise modeling of Cedar components. Its proof assistant enables fast proof development and verification. And Lean’s runtime supports efficient differential testing against the models.
If you’d like to try Lean for your own verification efforts, lean into the learning curve, start simple, and stay flexible! It can be rewarding and a lot of fun.
To learn more about Lean and Cedar:
Check out the Lean proof assistant and join the thriving community around it.
Try out Cedar policies in the online playground.
Explore Cedar’s Lean models and differential testing framework on GitHub.
Join the Cedar Slack channel to connect with the team.
Check out a Cedar demo and talk to our team in the AWS booth at Open Source Summit in Seattle on April 16-18, 2024.
