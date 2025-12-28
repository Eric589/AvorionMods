# Avorion API Documentation Conversion Guide

This guide explains how to convert the HTML documentation files to YAML format for better readability and maintainability.

## Why Convert to YAML?

- **Human-readable**: YAML is much easier to read than HTML
- **Structured data**: Clear hierarchy and organization
- **Easy to parse**: Can be processed by scripts and tools
- **Better searchability**: Plain text format enables better text search
- **Version control friendly**: Cleaner diffs in git
- **Documentation as code**: Treat API docs like code

## Conversion Template

See `YAML-TEMPLATE.yaml` for the complete template structure.

## File Naming Convention

Convert `ClassName.html` to `ClassName.yaml`:
- `ArrowLine.html` → `ArrowLine.yaml`
- `Entity.html` → `Entity.yaml`
- `FighterController.html` → `FighterController.yaml`
- `Alliance [Server].html` → `Alliance [Server].yaml`

## HTML to YAML Mapping

### Basic Class Structure

**HTML:**
```html
<h1>ClassName : BaseClass</h1>
<span class="warning">This object is only available on the client.</span>
```

**YAML:**
```yaml
name: ClassName
type: class
extends: BaseClass
availability: client-only  # or server-only, or both
```

### Constructor

**HTML:**
```html
<span class="keyword">function </span> ClassName(<span class="type">int</span> <span class="parameter">index</span>)
```

**YAML:**
```yaml
constructor:
  signature: ClassName(int index)
  parameters:
    - name: index
      type: int
      description: Index identifier
  returns: ClassName instance
```

### Properties

**HTML:**
```html
<span class="keyword">property</span> <span class="type">Color </span> <span class="property">color</span>
<td align="right"><span><b>[write-only]</b></span></td>
```

**YAML:**
```yaml
properties:
  - name: color
    type: Color
    access: write-only  # or read-only, or read-write
    description: Color of the element
```

For inherited properties:
```yaml
  - name: visible
    type: bool
    access: read-write
    inherited: UIElement
    description: Visibility state
```

### Methods

**HTML:**
```html
<span class="keyword">function void</span> methodName(<span class="type">int</span> <span class="parameter">param</span>)
```

**YAML:**
```yaml
methods:
  - name: methodName
    signature: methodName(int param)
    parameters:
      - name: param
        type: int
        description: Parameter description
    returns: void
    description: What the method does
```

For inherited methods:
```yaml
  - name: show
    signature: show()
    returns: void
    inherited: UIElement
    description: Shows the UI element
```

### Callbacks

For callback documentation files:
```yaml
name: Entity Callbacks
type: callbacks
scope: entity-attached scripts
availability: both  # or client-only or server-only

callbacks:
  - name: initialize
    signature: initialize()
    timing: Called when script is first added to entity
    returns: void

  - name: secure
    signature: secure()
    timing: Called before sector save
    returns: table
    description: Return table of state to persist

  - name: restore
    signature: restore(table data)
    timing: Called on sector load
    parameters:
      - name: data
        type: table
        description: Persisted state from secure()
```

### Enums

For the Enums.html file:
```yaml
name: ComponentType
type: enum
description: Component types for entity components

values:
  - name: FighterController
    value: ComponentType.FighterController
    description: Fighter deployment controller

  - name: FighterAI
    value: ComponentType.FighterAI
    description: Individual fighter AI
```

### Functions (Utility Functions)

For function documentation files like EntityFunctions.html:
```yaml
name: Entity Functions
type: utility_functions
description: Predefined utility functions for entity operations

functions:
  - name: functionName
    signature: functionName(param1, param2)
    parameters:
      - name: param1
        type: string
        description: Description
    returns:
      type: bool
      description: Return value description
    usage: |
      Example usage code
```

## Access Modifiers

Convert HTML indicators to YAML:
- `[read-only]` → `access: read-only`
- `[write-only]` → `access: write-only`
- No indicator → `access: read-write`

## Availability Markers

Convert HTML warnings to YAML:
- "This object is only available on the client" → `availability: client-only`
- "This object is only available on the server" → `availability: server-only`
- No warning → `availability: both`

## Inherited Members

For inherited properties/methods:
```yaml
properties:
  - name: visible
    type: bool
    access: read-write
    inherited: UIElement  # <-- Add this field
    description: Visibility state
```

## Adding Missing Information

The HTML documentation is auto-generated and often lacks descriptions. When converting, add helpful descriptions:

**Before (HTML has no description):**
```html
<span class="property">color</span>
<div style="padding-left:20px; padding-bottom:10px">
</div>
```

**After (YAML with description):**
```yaml
- name: color
  type: Color
  access: write-only
  description: Color of the arrow line
```

## Special Cases

### Split Server/Client Classes

For files like `Player [Server].html` and `Player [Client].html`:
```yaml
name: Player
variant: server  # or client
type: class
availability: server-only  # or client-only
```

### Classes with Multiple Constructors

```yaml
constructors:
  - signature: ClassName()
    description: Default constructor

  - signature: ClassName(int index)
    parameters:
      - name: index
        type: int
        description: Entity index
```

### Callback Documentation

Keep the callback pattern clear:
```yaml
type: callbacks
required_callbacks:
  - initialize
  - secure
  - restore

optional_callbacks:
  - updateServer
  - updateClient
  - getUpdateInterval
```

## Validation Checklist

After converting a file, verify:

- [ ] Class name matches filename
- [ ] Inheritance chain is correct
- [ ] All properties have type and access level
- [ ] All methods have signature and return type
- [ ] Inherited members are marked
- [ ] Availability (client/server/both) is specified
- [ ] Descriptions are added where missing
- [ ] Example code is included if applicable
- [ ] Cross-references to related classes are included

## Example Conversions

### Simple UI Element

See `ArrowLine.yaml` for a complete example of a UI element conversion.

### Component Class

```yaml
name: FighterController
type: component
availability: server-only
description: Controls fighter deployment and management on mothership

constructor:
  signature: FighterController(int entityId)
  parameters:
    - name: entityId
      type: int
      description: Entity ID of the mothership

properties:
  - name: entity
    type: Entity
    access: read-only
    description: The mothership entity

methods:
  - name: launchFighter
    signature: launchFighter(FighterTemplate template)
    parameters:
      - name: template
        type: FighterTemplate
        description: Fighter configuration
    returns:
      type: Entity
      description: The launched fighter entity
```

### Utility Functions

```yaml
name: SectorFunctions
type: utility_functions
description: Helper functions for sector operations

functions:
  - name: getRandomPosition
    signature: getRandomPosition(vec2 min, vec2 max)
    parameters:
      - name: min
        type: vec2
        description: Minimum coordinates
      - name: max
        type: vec2
        description: Maximum coordinates
    returns:
      type: vec2
      description: Random position in range
```

## Conversion Priority

Convert in this order:
1. Most commonly used classes (Entity, Sector, Player, FighterController, etc.)
2. UI classes (since they're all related via UIElement)
3. Component classes
4. Utility objects
5. Enum documentation
6. Callback documentation

## Automation

Consider writing a script to automate parts of the conversion:
1. Parse HTML structure
2. Extract class name, properties, methods
3. Generate YAML skeleton
4. Manual review and enhancement

## Notes

- HTML documentation is auto-generated and may be incomplete
- YAML conversion is an opportunity to add missing descriptions
- Cross-reference related classes in the YAML
- Add usage examples where helpful
- Link to the API-INDEX.yaml for context
